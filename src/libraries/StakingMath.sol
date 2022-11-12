pragma solidity ^0.8.15;

library StakingMath {
    struct ValueVariables {
        // The amount of tokens staked in the position or the contract.
        uint96 balance;
        // The sum of each staked token in the position or contract multiplied by its update time.
        uint160 sumOfEntryTimes;
    }

    struct RewardSummations {
        // Imaginary rewards accrued by a position with `lastUpdate == 0 && balance == 1`. At the
        // end of each interval, the ideal position has a staking duration of `block.timestamp`.
        // Since its balance is one, its “value” equals its staking duration. So, its value
        // is also `block.timestamp` , and for a given reward at an interval, the ideal position
        // accrues `reward * block.timestamp / totalValue`. Refer to `Ideal Position` section of
        // the Proofs on why we need this variable.
        uint256 idealPosition;
        // The sum of `reward/totalValue` of each interval. `totalValue` is the sum of all staked
        // tokens multiplied by their respective staking durations.  On every update, the
        // `rewardPerValue` is incremented by rewards given during that interval divided by the
        // total value, which is average staking duration multiplied by total staked. See Proofs.
        uint256 rewardPerValue;
    }

    struct Account {
        // Two variables that determine the share of rewards a position receives.
        ValueVariables valueVariables;
        // Summations snapshotted on the last update of the position.
        RewardSummations rewardSummationsPaid;
        // The sum of values (`balance * (block.timestamp - lastUpdate)`) of previous intervals. It
        // is only updated accordingly when more tokens are staked into an existing position. Other
        // calls than staking (i.e.: harvest and withdraw) must reset the value to zero. Correctly
        // updating this property allows for the staking duration of the existing balance of the
        // position to not restart when staking more tokens to the position. So it allows combining
        // together multiple positions with different staking durations. Refer to the `Combined
        // Positions` section of the Proofs on why this works.
        uint160 previousValues;
        // The last time the position was updated.
        uint48 lastUpdate;
    }

    uint256 private constant PRECISION = 2**128;


    function _earned(RewardSummations memory deltaRewardSummations, Account storage position)
        internal
        view
        returns (uint256)
    {
        if (position.lastUpdate == 0) {
            return 0;
        }
        uint256 PositionAgainstNegative = (deltaRewardSummations.idealPosition - (deltaRewardSummations.rewardPerValue * position.lastUpdate));
        uint256 Earned = (PositionAgainstNegative * position.valueVariables.balance) + (deltaRewardSummations.rewardPerValue * position.previousValues);
        uint256 ScaledEarned = Earned / PRECISION;

        return ScaledEarned;
    }

    function _getValue(ValueVariables memory valueVariables) internal view returns (uint256) {
        return block.timestamp * valueVariables.balance - valueVariables.sumOfEntryTimes;
    }

    function rewardRate(uint256 periodEnd, uint256 _rewardRate) internal view returns (uint256) {
        return periodEnd < block.timestamp ? 0 : _rewardRate;
    }
}