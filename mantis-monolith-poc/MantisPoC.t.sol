// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CoinDAOFactory} from "../src/CoinDAOFactory.sol";
import {IMonolithFactory, IMonolithLender} from "../src/interfaces/IMonolith.sol";

/// @notice PoC: CoinDAOFactory.deploy() is unexecutable against the canonical Monolith repo Lender.
/// The repo's Lender.sol (all public history) caps setLocalReserveFeeBps at 1000 bps
/// ("Invalid fee"), but CoinDAOFactory.DEFAULT_LOCAL_RESERVE_FEE_BPS = 5_000 and deploy()
/// applies it unconditionally right after monolithFactory.deploy(). The in-repo mock
/// (test/mocks/MockMonolith.sol:62) allows 5_000, so the suite never trips.
contract MantisPoC is Test {
    CoinDAOFactory factory;

    // Strict mock mirroring the canonical repo Lender fee cap (Monolith/src/Lender.sol:869).
    function setUp() public {
        IMonolithFactory.DeployParams memory empty;
        factory = new CoinDAOFactory(
            IMonolithFactory(address(new StrictMonolithFactory())),
            address(0xBEEF),
            _impls(address(new GovTokenImpl()), address(new StakedGovTokenImpl()), address(new RevenueRouterImpl()), address(new StakingRewardsImpl()), address(new StakingRewardsFunderImpl()), address(new VestingImpl()), address(new GovernorImpl()), address(new TimelockImpl()))
        );
    }

    function test_deployRevertsAgainstCanonicalLenderFeeCap() public {
        CoinDAOFactory.GovLaunchParams memory params;
        params.govTokenName = "Test Gov";
        params.govTokenSymbol = "TGOV";
        params.deployerStakeBps = 0;
        IMonolithFactory.DeployParams memory monolithParams;
        vm.expectRevert(); // Monolith Lender: "Invalid fee" (1000 bps cap < DEFAULT_LOCAL_RESERVE_FEE_BPS 5000)
        factory.deploy(bytes32("salt"), params, monolithParams, address(this));
    }

    function test_mockAllows5000SoRepoSuiteMasksIt() public {
        // Same call against the shipped MockMonolithLender (cap 5000) succeeds => the
        // repository's own suite can never catch the divergence.
        CoinDAOFactory govFactory = new CoinDAOFactory(
            IMonolithFactory(address(new LenientMonolithFactory())),
            address(0xBEEF),
            _impls(address(new GovTokenImpl()), address(new StakedGovTokenImpl()), address(new RevenueRouterImpl()), address(new StakingRewardsImpl()), address(new StakingRewardsFunderImpl()), address(new VestingImpl()), address(new GovernorImpl()), address(new TimelockImpl()))
        );
        CoinDAOFactory.GovLaunchParams memory params;
        params.govTokenName = "Test Gov";
        params.govTokenSymbol = "TGOV";
        params.deployerStakeBps = 0;
        IMonolithFactory.DeployParams memory monolithParams;
        CoinDAOFactory.Deployment memory d = govFactory.deploy(bytes32("salt"), params, monolithParams, address(this));
        assertGt(d.govToken.code.length, 0);
    }

    function _impls(address a, address b, address c, address d, address e, address f, address g, address h)
        internal
        pure
        returns (CoinDAOFactory.Implementations memory)
    {
        return CoinDAOFactory.Implementations({
            govToken: a,
            stakedGovToken: b,
            revenueRouter: c,
            stakingRewards: d,
            stakingRewardsFunder: e,
            vestingWallet: f,
            governor: g,
            timelock: h
        });
    }
}

// ---------- Lenient factory chain: mirrors the shipped MockMonolith (cap 5000) ----------

contract MockLender {
    address public operator;
    address public pendingOperator;
    address public coin;
    address public vault;
    uint16 public feeBps;

    constructor(address coin_, address vault_, address operator_) {
        operator = operator_;
        coin = coin_;
        vault = vault_;
    }

    function setPendingOperator(address p) external {
        pendingOperator = p;
    }

    function acceptOperator() external {
        require(msg.sender == pendingOperator, "Unauthorized");
        operator = pendingOperator;
        pendingOperator = address(0);
    }

    function setLocalReserveFeeBps(uint256 newFeeBps) external {
        require(newFeeBps <= 5_000, "Invalid fee");
        feeBps = uint16(newFeeBps);
    }

    function pullLocalReserves() external {}
    function setManager(address) external {}
    function enableImmutabilityNow() external {}
}

contract MockCoin {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
    }
}

contract LenientMonolithFactory {
    function deploy(IMonolithFactory.DeployParams calldata params)
        external
        returns (address lender, address coin, address vault)
    {
        MockCoin c = new MockCoin();
        MockLender l = new MockLender(address(c), address(c), params.operator);
        return (address(l), address(c), address(c));
    }
}

contract StrictMonolithFactory {
    function deploy(IMonolithFactory.DeployParams calldata params) external returns (address lender, address coin, address vault) {
        MockCoin c = new MockCoin();
        StrictLender l = new StrictLender(address(c), address(c), params.operator);
        return (address(l), address(c), address(c));
    }

    function isDeployed(address) external pure returns (bool) {
        return true;
    }
}

contract StrictLender {
    address public operator;
    address public pendingOperator;
    address public coin;
    address public vault;

    constructor(address coin_, address vault_, address operator_) {
        operator = operator_;
        coin = coin_;
        vault = vault_;
    }

    function setPendingOperator(address p) external {
        pendingOperator = p;
    }

    function acceptOperator() external {
        require(msg.sender == pendingOperator, "Unauthorized");
        operator = pendingOperator;
        pendingOperator = address(0);
    }

    // Canonical Monolith/src/Lender.sol:869
    function setLocalReserveFeeBps(uint256 _feeBps) external {
        require(_feeBps <= 1000, "Invalid fee");
    }

    function pullLocalReserves() external {}
}


contract GovTokenImpl {
    string public name;
    string public symbol;
    mapping(address => uint256) public balanceOf;

    function initialize(string memory n, string memory s, address holder) external {
        name = n;
        symbol = s;
        balanceOf[holder] = 10_000_000 ether;
    }

    function transfer(address to, uint256 v) external returns (bool) {
        balanceOf[msg.sender] -= v;
        balanceOf[to] += v;
        return true;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }
}

contract StakedGovTokenImpl {
    string public name;
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function initialize(address, address, string memory n, string memory, address) external {
        name = n;
    }

    function depositFor(address a, uint256 v) external returns (bool) {
        balanceOf[a] += v;
        totalSupply += v;
        return true;
    }

    function withdrawTo(address a, uint256 v) external returns (bool) {
        balanceOf[a] -= v;
        totalSupply -= v;
        return true;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }
}

contract RevenueRouterImpl {
    address public lender;
    address public coin;
    address public treasury;
    address public govStaking;
    address public owner;

    function initialize(address l, address c, address t, address g, uint16, address o) external {
        lender = l;
        coin = c;
        treasury = t;
        govStaking = g;
        owner = o;
    }

    function acceptLenderOperator() external {
        IMonolithLender(lender).acceptOperator();
    }

    function transferOwnership(address o) external {
        owner = o;
    }

    function distribute() external returns (uint256, uint256) {
        return (0, 0);
    }
}

contract StakingRewardsImpl {
    address public stakingToken;
    address public rewardsToken;
    address public rewardsDistribution;
    address public owner;
    uint256 public periodFinish;

    function initialize(address st, address rt, address o, uint256) external {
        stakingToken = st;
        rewardsToken = rt;
        owner = o;
        rewardsDistribution = o;
    }

    function setRewardsDistribution(address d) external {
        rewardsDistribution = d;
    }

    function notifyRewardAmount(uint256) external {}

    function renounceOwnership() external {}
}

contract StakingRewardsFunderImpl {
    address public stakingRewards;
    address public rewardsToken;
    uint256 public totalRewards;
    uint256 public nextTranche;

    function initialize(address sr, uint256 total) external {
        stakingRewards = sr;
        totalRewards = total;
    }

    function fundNextTranche() external {}
}

contract VestingImpl {
    function initialize(address, uint64, uint64) external {}
    function release() external {}
    function release(address) external {}
    receive() external payable {}
}

contract GovernorImpl {
    function initialize(string memory, address, address, uint256, uint256) external {}
}

contract TimelockImpl {
    function initialize(uint256, address[] memory, address[] memory, address) external {}
    function grantRole(bytes32, address) external {}
    function renounceRole(bytes32, address) external {}
    function PROPOSER_ROLE() external pure returns (bytes32) {
        return bytes32(uint256(1));
    }
    function CANCELLER_ROLE() external pure returns (bytes32) {
        return bytes32(uint256(2));
    }
    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32) {
        return bytes32(uint256(0));
    }
}
