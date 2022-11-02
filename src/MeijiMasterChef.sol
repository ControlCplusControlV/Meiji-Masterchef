// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./interfaces/IERC20.sol";
import "./libraries/Math.sol";

// Each Minion Chef handles serving just one pool, as directed by the MasterChef
contract MeijiMinionChef {

    enum PoolType {
        TridentConstantProduct,
        TridentStablePool,
        TridentConcentratedLiquidity,
        ClassicPool
    }

    struct Pool {
        PoolType Type;
        address PoolAddress;
        uint64 PoolCreatedTime;
    }

    struct Account {
        uint128 amount; // Amount of either Liquidity or Liquidity Tokens, would be insane for it to pass uint128 in any reasonable scenario
        uint96 rewardDebt; // Amount of Sushi Owed to the User
        uint32 depositedTime; // Amount of time liquidity has been locked in UNIX Time
    }

    struct RewardsCache {
        uint32 NumberOfStakers;
        uint224 StakeTimeSum;
        /*
            Average Staking Duration is tracked in a unique way, we store the sqrt(sum of all (amount * duration))
            for every position in the chef, with the square root at the end purely being for size constraints. To ensure
            this is always accurate we update this 
        */
    }

    mapping(address => Account) public accounts;
    Pool public pool;

    constructor(IERC20 Pair, IERC20 RewardToken) {
        // Reward Token will usually be Sushi
        
    }

    function deposit(uint256 amount) external {
        

    }

    function withdraw() external {
        
    }

    function StdDev(RewardsCache memory rewards) internal pure returns (uint256 StdDev) {
        uint256 populationValues = rewards.StakeTimeSum - (rewards.StakeTimeSum / rewards.NumberOfStakers);
        StdDev = Math.sqrt(Math.mulDiv(populationValues, populationValues, rewards.NumberOfStakers));
    }

}
