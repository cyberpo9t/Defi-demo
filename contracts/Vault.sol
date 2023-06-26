// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "hardhat/console.sol";

interface IStargateRouter {
  struct lzTxObj {
    uint256 dstGasForCall;
    uint256 dstNativeAmount;
    bytes dstNativeAddr;
  }

  function addLiquidity(
    uint256 _poolId,
    uint256 _amountLD,
    address _to
  ) external;

  function swap(
    uint16 _dstChainId,
    uint256 _srcPoolId,
    uint256 _dstPoolId,
    address payable _refundAddress,
    uint256 _amountLD,
    uint256 _minAmountLD,
    lzTxObj memory _lzTxParams,
    bytes calldata _to,
    bytes calldata _payload
  ) external payable;

  function redeemLocal(
    uint16 _dstChainId,
    uint256 _srcPoolId,
    uint256 _dstPoolId,
    address payable _refundAddress,
    uint256 _amountLP,
    bytes calldata _to,
    lzTxObj memory _lzTxParams
  ) external payable;

  function instantRedeemLocal(
    uint16 _srcPoolId,
    uint256 _amountLP,
    address _to
  ) external returns (uint256);
}

interface IStargateLPStaking {
  struct UserInfo {
    uint256 amount; // How many LP tokens the user has provided.
    uint256 rewardDebt; // Reward debt. See explanation below
  }

  function deposit(uint256 _pid, uint256 _amount) external;

  function withdraw(uint256 _pid, uint256 _amount) external;

  function userInfo(
    uint256 _pid,
    address _account
  ) external view returns (UserInfo memory);
  // mapping(uint256 => mapping(address => UserInfo)) public userInfo;
}

using SafeERC20 for IERC20;

interface IERC20Burnable is IERC20 {
  function burn(uint256 amount) external;

  function burnFrom(address account, uint256 amount) external;

  function mint(address to, uint256 amount) external;

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);
}

contract Vault is Ownable {
  // 已被mint的份额（shares）
  uint256 internal totalSupply;
  // 已被deposit的资产数
  uint256 internal total_debt;
  // 未被deposit的资产数，被vault合约持有的
  uint256 internal total_idle;

  // event事件
  // 用户deposit
  event Deposit(uint256 indexed _amount);
  // 管理员harvest
  event Harvest(uint256 indexed _amount);
  // 管理员投资
  event Invesment(uint256 indexed _amount);
  // 用户撤回资金
  event Redeem(uint256 indexed _shares, uint256 indexed _assets);
  // uniswap兑换
  event SwapWithUniswap(uint256 indexed _in, uint256 indexed _out);

  event InvestmentSUSDT(uint256 indexed _amout);
  event TotalIdle(uint256 indexed _amount);

  address vaultToken;
  IERC20Burnable internal shares;
  IERC20 internal usdt = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
  address STARGATE_ROUTER = 0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614;
  IStargateRouter internal stargate_router = IStargateRouter(STARGATE_ROUTER);
  address STARGATE_LPSTAKING = 0xeA8DfEE1898a7e0a59f7527F076106d7e44c2176;
  IStargateLPStaking internal stargate_lpstaking =
    IStargateLPStaking(STARGATE_LPSTAKING);
  IERC20 internal susdt = IERC20(0xB6CfcF89a7B22988bfC96632aC2A9D6daB60d641);
  IERC20 internal stg = IERC20(0x6694340fc020c5E6B96567843da2df01b2CE1eb6);

  // uniswap设置
  uint24 public constant poolFee = 3000;
  address public constant STG = 0x6694340fc020c5E6B96567843da2df01b2CE1eb6;
  address public constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
  address public constant UniSwap = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  ISwapRouter public swapRouter = ISwapRouter(UniSwap);

  constructor() {
    // 创建VaultToken管理份额
    vaultToken = address(new VaultToken());
    shares = IERC20Burnable(vaultToken);
  }

  // 读取vault总资产
  function totalAssets() external view onlyOwner returns (uint256) {
    return _total_assets();
  }

  // 读取vaultToken地址
  function getVaultTokenAddress() external view returns (address) {
    return vaultToken;
  }

  // 用户传入USDT数量进行投资
  function deposit(uint256 _amount) external payable {
    console.log("start deposit...");
    uint256 total_supply = _total_supply();
    uint256 total_assets = _total_assets();
    uint256 new_shares = 0;

    if (total_supply == 0) {
      new_shares = _amount;
    } else if (total_assets > _amount) {
      new_shares = (_amount * total_supply) / total_assets;
    } else {
      assert(total_assets > _amount);
    }

    // 转入usdt到vault
    usdt.safeTransferFrom(msg.sender, address(this), _amount);
    // 铸造VT发放给用户
    shares.mint(msg.sender, _amount);
    // 更新idle资金
    total_idle += _amount;

    console.log("deposit done.");
    emit Deposit(_amount);
  }

  // struct UserInfo {
  //   uint256 amount; // How many LP tokens the user has provided.
  //   uint256 rewardDebt; // Reward debt. See explanation below
  // }

  // 管理员撤回所有投资兑换成USDT
  function harvest() external onlyOwner {
    console.log("start harvest...");
    // 在lpstaking中查询总投资额
    IStargateLPStaking.UserInfo memory userInfo = stargate_lpstaking.userInfo(
      1,
      address(this)
    );

    // 从lpstaking中撤回投资得到susdt和stg
    stargate_lpstaking.withdraw(1, userInfo.amount);
    //获取susdt数量
    uint256 susdt_amount = susdt.balanceOf(address(this));
    console.log("susdt_amount: ", susdt_amount);
    // 将susdt置换成usdt
    uint256 sustdToUsdt_amount = stargate_router.instantRedeemLocal(
      2,
      susdt_amount,
      address(this)
    );
    // 获取stg数量
    uint256 stg_amount = stg.balanceOf(address(this));
    // 给uniswap授权stg
    stg.approve(UniSwap, stg_amount);
    // 将stg置换成usdt
    uint256 stgToUsdt_amount = _swapExactInputSingle(stg_amount);
    // 更新资产数
    total_debt = 0;
    total_idle += sustdToUsdt_amount + stgToUsdt_amount;
    console.log("total_idle: ", total_idle);
    console.log("harvest done.");
    emit Harvest(sustdToUsdt_amount + stgToUsdt_amount);
  }

  // 管理员开启投资，使用idle资金
  function investment() external onlyOwner {
    console.log("start investment...");
    require(total_idle > 0);
    emit TotalIdle(total_idle);

    // 给router授权
    usdt.approve(STARGATE_ROUTER, total_idle);
    // 注入流动性，获得S*USDT
    stargate_router.addLiquidity(2, total_idle, address(this));
    // 获取S*USDT数量
    uint256 susdt_amount = susdt.balanceOf(address(this));
    console.log("susdt_amount: ", susdt_amount);
    // 给lpstaking授权susdt
    susdt.approve(STARGATE_LPSTAKING, susdt_amount);
    // 使用S*USDT投入lpstaking
    stargate_lpstaking.deposit(1, susdt_amount);
    // 更新idle和debt
    total_debt += total_idle;
    total_idle = 0;

    console.log("investment done.");
    emit Invesment(total_idle);
  }

  // 用户使用VT撤回资金
  function redeem(uint256 _amount) external {
    console.log("start redeem...");
    require(_amount > 0);

    uint256 total_supply = _total_supply();
    uint256 total_assets = _total_assets();
    console.log("total_supply: ", total_supply);
    console.log("total_assets: ", total_assets);
    // 计算VT份额对应的usdt数
    uint256 assets = (_amount * total_assets) / total_supply;
    console.log("assets: ", assets);
    require(assets >= _amount);
    // 用户转账VT到vault
    shares.transferFrom(msg.sender, address(this), _amount);
    // 销毁VT
    console.log("burn VT: ", _amount);
    shares.burn(_amount);
    // 更新idle
    total_idle -= assets;
    // 给用户打钱
    console.log("trasfer: ", assets);
    usdt.transfer(msg.sender, assets);

    console.log("redeem done.");
    emit Redeem(_amount, assets);
  }

  // // 计算资产转换成份额的数量
  // function _convertToShares(uint256 _assets) internal {}

  // // 计算份额转换成资产的数量
  // function _convertToAssets(uint256 _shares) internal {}

  // 获取totalSupply
  function _total_supply() internal view returns (uint256) {
    return shares.totalSupply();
  }

  // 获取total_assets
  function _total_assets() internal view returns (uint256) {
    return total_debt + total_idle;
  }

  // uniswap兑换
  function _swapExactInputSingle(
    uint256 amountIn
  ) internal returns (uint256 amountOut) {
    // msg.sender must approve this contract
    // TransferHelper.safeTransferFrom(STG, msg.sender, address(this), amountIn);
    TransferHelper.safeApprove(STG, address(swapRouter), amountIn);
    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
      .ExactInputSingleParams({
        tokenIn: STG,
        tokenOut: USDT,
        fee: poolFee,
        recipient: address(this),
        deadline: block.timestamp,
        amountIn: amountIn,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      });
    amountOut = swapRouter.exactInputSingle(params);

    emit SwapWithUniswap(amountIn, amountOut);
  }
}

contract VaultToken is ERC20, ERC20Burnable, Ownable {
  constructor() ERC20("VaultToken", "VT") {}

  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  }
}
