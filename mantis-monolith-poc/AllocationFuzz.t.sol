// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {CoinDAOFactory} from "../src/CoinDAOFactory.sol";
import {IMonolithFactory} from "../src/interfaces/IMonolith.sol";

contract AllocationHarness is CoinDAOFactory {
    constructor() CoinDAOFactory(IMonolithFactory(address(1)), address(1), _zeroImpls()) {}

    function _zeroImpls() internal pure returns (Implementations memory i) {
        i.govToken = address(0xdead);
        i.stakedGovToken = address(0xdead1);
        i.revenueRouter = address(0xdead2);
        i.stakingRewards = address(0xdead3);
        i.stakingRewardsFunder = address(0xdead4);
        i.vestingWallet = address(0xdead5);
        i.governor = address(0xdead6);
        i.timelock = address(0xdead7);
    }
}

/// @notice Fuzz: allocationFor must fully allocate the fixed GOV supply (value conservation)
/// and monotonically move value from staking-rewards+treasury into deployer stake.
contract AllocationFuzz is Test {
    AllocationHarness h;

    function setUp() public {
        bytes memory code = hex"600a"; // any non-empty code passes _validateImplementations
        vm.etch(address(0xdead), code);
        vm.etch(address(0xdead1), code);
        vm.etch(address(0xdead2), code);
        vm.etch(address(0xdead3), code);
        vm.etch(address(0xdead4), code);
        vm.etch(address(0xdead5), code);
        vm.etch(address(0xdead6), code);
        vm.etch(address(0xdead7), code);
        h = new AllocationHarness();
    }

    function testFuzz_allocationFullyConservesSupply(uint16 deployerStakeBps) public view {
        vm.assume(deployerStakeBps <= 2_000);
        CoinDAOFactory.AllocationAmounts memory a = h.allocationFor(deployerStakeBps);
        uint256 sum = a.coinStakingRewards + a.treasuryVested + a.immediateAllocation + a.monolithVesting
            + a.deployerVesting;
        assertEq(sum, 10_000_000 ether, "supply must be fully allocated");
    }

    function testFuzz_deployerStakeGrowsLinearlyAndReducesRemaining(uint16 bps) public {
        vm.assume(bps <= 2_000);
        CoinDAOFactory.AllocationAmounts memory a = h.allocationFor(bps);
        console2.log("dep", a.deployerVesting);
        console2.log("imm", a.immediateAllocation);
        console2.log("mono", a.monolithVesting);
        uint256 wantDep = (uint256(bps) * 1e25) / 10_000;
        assertEq(a.deployerVesting, wantDep);
        assertEq(a.immediateAllocation, 5e23);
        assertEq(a.monolithVesting, 2e23);
        // Reference recomputation with stepwise logs to isolate the panic.
        console2.log("stk", a.coinStakingRewards);
        console2.log("tsy", a.treasuryVested);
        uint256 remaining = 10_000_000 ether;
        console2.log("r0", remaining);
        remaining -= a.deployerVesting;
        console2.log("r1", remaining);
        remaining -= a.immediateAllocation;
        console2.log("r2", remaining);
        remaining -= a.monolithVesting;
        console2.log("r3", remaining);
        uint256 wantStaking = (remaining * 6_500) / 9_300;
        assertEq(a.coinStakingRewards, wantStaking);
        assertEq(a.treasuryVested, remaining - a.coinStakingRewards);
    }
}
