pragma solidity ^0.8.15;

import "./Ledger.sol";
import "./libraries/StakingMath.sol";
import "./interfaces/IERC20.sol";
import "./libraries/GenericErrors.sol";

contract MeijiChef is Ledger, GenericErrors {
    IERC20 RewardToken = IERC20(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2);

    /** @notice The event emitted when withdrawing or harvesting from a position. */
    event Withdrawn(uint256 indexed positionId, uint256 indexed amount, uint256 indexed reward);

    /** @notice The event emitted when staking to, minting, or compounding a position. */
    event Staked(uint256 indexed positionId, uint256 indexed amount, uint256 indexed reward);

    // Core Functions
    function stake(uint256 positionId, uint256 amount) external {
        // Update summations. Note that rewards accumulated when there is no one staking will
        // be lost. But this is only a small risk of value loss when the contract first goes live.
        _updateRewardSummations();

        // Use a private function to handle the logic pertaining to depositing into a position.
        _stake(positionId, amount);
    }

    /**
     * @notice External function to claim the accrued rewards of a position.
     * @param positionId The identifier of the position to claim the rewards of.
     */
    function harvest(uint256 positionId) external {
        // Update summations that govern the reward distribution.
        _updateRewardSummations();

        // Use a private function to handle the logic pertaining to harvesting rewards.
        // `_withdraw` with zero input amount works as harvesting.
        _withdraw(positionId, 0);
    }

    /**
     * @notice External function to deposit the accrued rewards of a position back to itself.
     * @param positionId The identifier of the position to compound the rewards of.
     */
    function compound(uint256 positionId) external {
        // Update summations that govern the reward distribution.
        _updateRewardSummations();

        // Use a private function to handle the logic pertaining to compounding rewards.
        // `_stake` with zero input amount works as compounding.
        _stake(positionId, 0);
    }

    /**
     * @notice External function to withdraw given amount of staked balance, plus all the accrued
     *         rewards from the position.
     * @param positionId The identifier of the position to withdraw the balance.
     * @param amount The amount of staked tokens, excluding rewards, to withdraw from the position.
     */
    function withdraw(uint256 positionId, uint256 amount) external {
        // Update summations that govern the reward distribution.
        _updateRewardSummations();

        // Use a private function to handle the logic pertaining to withdrawing the staked balance.
        _withdraw(positionId, amount);
    }

    // Internal Functions
    function _stake(uint8 index ,address owner, uint256 amount) internal {
        // Create a storage pointer for the position.
        Account storage position = accounts[owner][index];

        // Get rewards accrued in the position.
        uint256 reward = _positionPendingRewards(position);

        // Include reward amount in total amount to be staked.
        uint256 totalAmount = amount + reward;
        if (totalAmount == 0) revert NoEffect();

        // Get the new total staked amount and ensure it fits 96 bits.
        uint256 newTotalStaked = totalValueVariables.balance + totalAmount;
        if (newTotalStaked > type(uint96).max) revert Overflow();

        unchecked {
            // Increment the state variables pertaining to total value calculation.
            uint160 addedEntryTimes = uint160(block.timestamp * totalAmount);
            totalValueVariables.sumOfEntryTimes += addedEntryTimes;
            totalValueVariables.balance = uint96(newTotalStaked);

            // Increment the position properties pertaining to position value calculation.
            ValueVariables storage positionValueVariables = position.valueVariables;
            uint256 oldBalance = positionValueVariables.balance;
            positionValueVariables.balance = uint96(oldBalance + totalAmount);
            positionValueVariables.sumOfEntryTimes += addedEntryTimes;

            // Increment the previousValues.
            position.previousValues += uint160(
                oldBalance * (block.timestamp - position.lastUpdate)
            );
        }

        // Snapshot the lastUpdate and summations.
        position.lastUpdate = uint48(block.timestamp);
        position.rewardSummationsPaid = rewardSummationsStored;

        // Transfer amount tokens from user to the contract, and emit the associated event.
        if (amount != 0) RewardToken.transferFrom(msg.sender, address(this), amount);
        emit Staked(index, amount, reward);
    }

    function _withdraw(uint8 index ,address owner, uint256 amount) internal {
        // Create a storage pointer for the position.
        Account storage position = accounts[owner][index];

        // Get position balance and ensure sufficient balance exists.
        uint256 oldBalance = position.valueVariables.balance;
        if (amount > oldBalance) revert InsufficientBalance();

        // Get accrued rewards of the position and get totalAmount to withdraw (incl. rewards).
        uint256 reward = _positionPendingRewards(position);
        uint256 totalAmount = amount + reward;
        if (totalAmount == 0) revert NoEffect();

        unchecked {
            // Get the remaining balance in the position.
            uint256 remaining = oldBalance - amount;

            // Decrement the withdrawn amount from totalStaked.
            totalValueVariables.balance -= uint96(amount);

            // Update sumOfEntryTimes.
            uint256 newEntryTimes = block.timestamp * remaining;
            ValueVariables storage positionValueVariables = position.valueVariables;
            totalValueVariables.sumOfEntryTimes = uint160(
                totalValueVariables.sumOfEntryTimes +
                    newEntryTimes -
                    positionValueVariables.sumOfEntryTimes
            );

            // Decrement the withdrawn amount from position balance and update position entryTimes.
            positionValueVariables.balance = uint96(remaining);
            positionValueVariables.sumOfEntryTimes = uint160(newEntryTimes);
        }

        // Reset the previous values, as we have restarted the staking duration.
        position.previousValues = 0;

        // Update lastDevaluation, as resetting the staking duration devalues the position.
        // position.lastDevaluation = uint48(block.timestamp);

        // Snapshot the lastUpdate and summations.
        position.lastUpdate = uint48(block.timestamp);
        position.rewardSummationsPaid = rewardSummationsStored;

        // Transfer withdrawn amount and rewards to the user, and emit the associated event.
        RewardToken.transfer(msg.sender, amount);

        emit Withdrawn(index, amount, reward);
    }

    function _positionPendingRewards(Account storage position) private view returns (uint256) {
        // Get the change in summations since the position was last updated. When calculating
        // the delta, do not increment `rewardSummationsStored`, as they had to be updated anyways.
        RewardSummations memory deltaRewardSummations;

        RewardSummations storage rewardSummationsPaid = position.rewardSummationsPaid;

        deltaRewardSummations= RewardSummations(
                rewardSummationsStored.idealPosition - rewardSummationsPaid.idealPosition,
                rewardSummationsStored.rewardPerValue - rewardSummationsPaid.rewardPerValue
        );

        if (position.lastUpdate == 0) {
            deltaRewardSummations = RewardSummations(0, 0);
        }

        // Return the pending rewards of the position.
        if (position.lastUpdate == 0) {
            return 0;
        }
        
        return (((deltaRewardSummations.idealPosition -
                (deltaRewardSummations.rewardPerValue * position.lastUpdate)) *
                position.valueVariables.balance) +
                (deltaRewardSummations.rewardPerValue * position.previousValues)) / (2**128);
    }

    function positionRewardRate(address owner, uint8 account) external view returns (uint256) {
        // Get totalValue and positionValue.
        uint256 totalValue = _getValue(totalValueVariables);
        uint256 positionValue = _getValue(accounts[owner][account].valueVariables);

        // Return the rewardRate of the position. Do not revert if totalValue is zero.
        return positionValue == 0 ? 0 : (StakingMath.rewardRate(periodFinish, _rewardRate) * positionValue) / totalValue;
    }

    function _earned(RewardSummations memory deltaRewardSummations, Account storage position)
        internal
        view
        returns (uint256)
    {
        // Refer to the Combined Position section of the Proofs on why and how this formula works.
        return
            position.lastUpdate == 0
                ? 0
                : (((deltaRewardSummations.idealPosition -
                    (deltaRewardSummations.rewardPerValue * position.lastUpdate)) *
                    position.valueVariables.balance) +
                    (deltaRewardSummations.rewardPerValue * position.previousValues)) / PRECISION;
    }

    function _getValue(ValueVariables storage valueVariables) internal view returns (uint256) {
        return block.timestamp * valueVariables.balance - valueVariables.sumOfEntryTimes;
    }

    function _updateRewardSummations() private {
        // Get rewards, in the process updating the last update time.
        uint256 rewards = _claim();

        // Get incrementations based on the reward amount.
        (
            uint256 idealPositionIncrementation,
            uint256 rewardPerValueIncrementation
        ) = _getRewardSummationsIncrementations(rewards);

        // Increment the summations.
        rewardSummationsStored.idealPosition += idealPositionIncrementation;
        rewardSummationsStored.rewardPerValue += rewardPerValueIncrementation;
    }

    function _getRewardSummationsIncrementations(uint256 rewards)
        private
        view
        returns (uint256 idealPositionIncrementation, uint256 rewardPerValueIncrementation)
    {
        // Calculate the totalValue, then get the incrementations only if value is non-zero.
        uint256 totalValue = _getValue(totalValueVariables);
        if (totalValue != 0) {
            idealPositionIncrementation = (rewards * block.timestamp * PRECISION) / totalValue;
            rewardPerValueIncrementation = (rewards * PRECISION) / totalValue;
        }
    }

    function _claim() internal returns (uint256 reward) {
        // Get the pending reward amount since last update was last updated.
        reward = _pendingRewards();

        // Update last update time.
        lastUpdate = uint40(block.timestamp);
    }

        function _pendingRewards() internal view returns (uint256 rewards) {
        // For efficiency, move periodFinish timestamp to memory.
        uint256 tmpPeriodFinish = periodFinish;

        // Get end of the reward distribution period or block timestamp, whichever is less.
        // `lastTimeRewardApplicable` is the ending timestamp of the period we are calculating
        // the total rewards for.
        uint256 lastTimeRewardApplicable = tmpPeriodFinish < block.timestamp
            ? tmpPeriodFinish
            : block.timestamp;

        // For efficiency, move lastUpdate timestamp to memory. `lastUpdate` is the beginning
        // timestamp of the period we are calculating the total rewards for.
        uint256 tmpLastUpdate = lastUpdate;

        // If the reward period is a positive range, return the rewards by multiplying the duration
        // by reward rate.
        if (lastTimeRewardApplicable > tmpLastUpdate) {
            unchecked {
                rewards = (lastTimeRewardApplicable - tmpLastUpdate) * _rewardRate;
            }
        }

        assert(rewards <= type(uint96).max);
    }

}