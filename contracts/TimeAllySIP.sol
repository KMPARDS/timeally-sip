pragma solidity 0.5.12;

contract TimeAllySIP {
  struct SIPPlan {
    bool isPlanActive;
    uint256 minimumCommitmentAmount;
    uint256 accumulationPeriodMonths; /// @dev 12 months
    uint256 benefitPeriodYears; /// @dev 9 years
    uint256 gracePeriodSeconds;
    uint256 onTimeBenefitFactor; /// @dev this is per 1000; i.e 200 for 20%
    uint256 graceBenefitFactor; /// @dev this is per 1000; i.e 180 for 18%
    uint256 topupBenefitFactor; /// @dev this is per 1000; i.e 100 for 10%
  }

  struct SIP {
    uint256 planId;
    uint256 stakingTimestamp;
    uint256 commitmentAmount;
    uint256 ctcAmount; /// @dev this amount is deposited by company for benefits
    uint256 pendingBenefitAmount; /// @dev increased everytime staker deposits
    uint256 powerBoosterAmount;
    uint256[] accumulationAmount;
  }

  address public owner;
  ERC20 public token;

  /// @dev 1 Year = 365.242 days for taking care of leap years
  uint256 public earthSecondsInMonth = 2629744;

  SIPPlan[] public sipPlans;

  mapping(address => SIP[]) public sips;

  modifier onlyOwner() {
    require(msg.sender == owner, 'only deployer can call');
    _;
  }

  constructor(ERC20 _token) public {
    owner = msg.sender;
    token = _token;
  }

  function createSIPPlan(
    uint256 _minimumCommitmentAmount,
    uint256 _accumulationPeriodMonths,
    uint256 _benefitPeriodYears,
    uint256 _gracePeriodSeconds,
    uint256 _onTimeBenefitFactor,
    uint256 _graceBenefitFactor,
    uint256 _topupBenefitFactor
  ) public onlyOwner {
    sipPlans.push(SIPPlan({
      isPlanActive: true,
      accumulationPeriodMonths: _accumulationPeriodMonths,
      minimumCommitmentAmount: _minimumCommitmentAmount,
      benefitPeriodYears: _benefitPeriodYears,
      gracePeriodSeconds: _gracePeriodSeconds,
      onTimeBenefitFactor: _onTimeBenefitFactor,
      graceBenefitFactor: _graceBenefitFactor,
      topupBenefitFactor: _topupBenefitFactor
    }));
  }


}

/// @dev For interface requirement
contract ERC20 {
  function balanceOf(address _owner) public view returns (uint256 balance);
  function transfer(address _to, uint256 _value) public returns (bool success);
  function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);
}

/// @dev TimeAlly Smart Contract (that rewards from NRT Manager). Purpose is to sync with the NRT month number.
contract TimeAlly {
  function getCurrentMonth() public view returns (uint256);
}
