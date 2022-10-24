//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./NftyDToken.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenVesting is Ownable, Pausable {
    uint256 private constant month = 30 days;
    uint256 private constant GENESIS_TIMESTAMP = 1514764800; // Jan 1, 2018 00:00:00 UTC (arbitrary date/time for timestamp validatio

    struct VestingGrant {
        bool isGranted; // Flag to indicate grant was issued
        address issuer; // Account that issued grant
        address beneficiary; // Beneficiary of grant
        uint256 grantDreams; // Number of dreams granted
        uint256 startTimestamp; // Start date/time of vesting
        uint256 cliffTimestamp; // Cliff date/time for vesting
        uint256 endTimestamp; // End date/time of vesting
        bool isRevocable; // Whether issuer can revoke and reclaim dreams
        uint256 releasedDreams; // Number of dreams already released
    }

    mapping(address => VestingGrant) public vestingGrants;
    mapping(address => bool) public authorizedAddresses; // Token grants subject to vesting
    address[] private vestingGrantLookup; // Lookup table of token grants

    NftyDToken public tokenContract;

    /* Vesting Events */
    event Grant(
        // Fired when an account grants tokens to another account on a vesting schedule
        address indexed owner,
        address indexed beneficiary,
        uint256 value
    );

    event Revoke(
        // Fired when an account revokes previously granted unvested tokens to another account
        address indexed owner,
        address indexed beneficiary,
        uint256 value
    );

    /**
     * @dev Constructor
     *
     * @param  _tokenContract Address of the WHENToken contract
     */
    constructor(address payable _tokenContract) {
        tokenContract = NftyDToken(_tokenContract);
    }

    /**
     * @dev Authorizes a smart contract to call this contract
     *
     * @param account Address of the calling smart contract
     */
    function authorizeAddress(address account) public whenNotPaused onlyOwner {
        require(account != address(0));

        authorizedAddresses[account] = true;
    }

    /**
     * @dev Deauthorizes a previously authorized smart contract from calling this contract
     *
     * @param account Address of the calling smart contract
     */
    function deauthorizeAddress(address account)
        external
        whenNotPaused
        onlyOwner
    {
        require(account != address(0));

        authorizedAddresses[account] = false;
    }

    /**
     * @dev Grants a beneficiary dreams using a vesting schedule
     *
     * @param beneficiary The account to whom dreams are being granted
     * @param dreams dreams that are granted but not vested
     * @param startTimestamp Date/time when vesting begins
     * @param cliffSeconds Date/time prior to which tokens vest but cannot be released
     * @param vestingSeconds Vesting duration (also known as vesting term)
     * @param revocable Indicates whether the granting account is allowed to revoke the grant
     */

    function grant(
        address beneficiary,
        uint256 dreams,
        uint256 startTimestamp,
        uint256 cliffSeconds,
        uint256 vestingSeconds,
        bool revocable
    ) external whenNotPaused {
        require(authorizedAddresses[msg.sender], "1");
        require(beneficiary != address(0), "2");
        require(!vestingGrants[beneficiary].isGranted, "3"); // Can't have multiple grants for same account
        require((dreams > 0), "4"); // There must be dreams that are being granted

        require(startTimestamp >= GENESIS_TIMESTAMP, "5"); // Just a way to prevent really old dates
        require(vestingSeconds > 0, "6");
        require(cliffSeconds >= 0, "7");
        require(cliffSeconds < vestingSeconds, "8");

        tokenContract.transferFrom(msg.sender, address(this), dreams);
        // The vesting grant is added to the beneficiary and the vestingGrant lookup table is updated
        vestingGrants[beneficiary] = VestingGrant({
            isGranted: true,
            issuer: msg.sender,
            beneficiary: beneficiary,
            grantDreams: dreams,
            startTimestamp: startTimestamp,
            cliffTimestamp: startTimestamp + cliffSeconds,
            endTimestamp: startTimestamp + vestingSeconds,
            isRevocable: revocable,
            releasedDreams: 0
        });

        vestingGrantLookup.push(beneficiary);

        emit Grant(msg.sender, beneficiary, dreams); // Fire event

        // If the cliff time has already passed or there is no cliff, then release
        // any dreams for which the beneficiary is already eligible
        if (vestingGrants[beneficiary].cliffTimestamp <= block.timestamp) {
            releaseFor(beneficiary);
        }
    }

    /**
     * @dev Releases dreams that have been vested for caller
     *
     */
    function release() external {
        releaseFor(msg.sender);
    }

    /**
     * @dev Gets current grant balance for caller
     *
     */
    function getGrantBalance() external view returns (uint256) {
        return getGrantBalanceOf(msg.sender);
    }

    /**
     * @dev Gets current grant balance for an account
     *
     * The return value subtracts dreams that have previously
     * been released.
     *
     * @param account Account whose grant balance is returned
     *
     */
    function getGrantBalanceOf(address account) public view returns (uint256) {
        require(account != address(0));
        require(vestingGrants[account].isGranted);

        return (vestingGrants[account].grantDreams -
            (vestingGrants[account].releasedDreams));
    }

    /**
     * @dev Returns a lookup table of all vesting grant beneficiaries
     *
     */
    function getGrantBeneficiaries() external view returns (address[] memory) {
        return vestingGrantLookup;
    }

    /**
     * @dev Releases dreams that have been vested for an account
     *
     * @param account Account whose dreams will be released
     *
     */
    function releaseFor(address account) public {
        require(account != address(0));
        require(vestingGrants[account].isGranted);
        require(
            vestingGrants[account].cliffTimestamp <= block.timestamp,
            "Cannot release tokens before cliff period"
        );

        // Calculate vesting rate per second
        uint256 vestingMonths = (vestingGrants[account].endTimestamp -
            (vestingGrants[account].startTimestamp)) / month;
        uint256 dreamsPerMonth = vestingGrants[account].grantDreams /
            vestingMonths;

        // Calculate how many dreams can be released
        uint256 monthsPassed = (block.timestamp -
            vestingGrants[account].startTimestamp) / month;

        uint256 releasableDreams = monthsPassed *
            (dreamsPerMonth) -
            (vestingGrants[account].releasedDreams);

        // If the additional released dreams would cause the total released to exceed total granted, then
        // cap the releasable dreams to whatever was granted.
        if (
            (vestingGrants[account].releasedDreams + (releasableDreams)) >
            vestingGrants[account].grantDreams
        ) {
            releasableDreams =
                vestingGrants[account].grantDreams -
                (vestingGrants[account].releasedDreams);
        }
        console.log("releasableDreams:", releasableDreams);

        if (releasableDreams > 0) {
            // Update the released dreams counter
            vestingGrants[account].releasedDreams =
                vestingGrants[account].releasedDreams +
                (releasableDreams);
            tokenContract.transferFrom(
                address(this),
                account,
                releasableDreams
            );
        }
    }

    /**
     * @dev Revokes previously issued vesting grant
     *
     * For a grant to be revoked, it must be revocable.
     * In addition, only the unreleased tokens can be revoked.
     *
     * @param account Account for which a prior grant will be revoked
     */
    function revoke(address account) public whenNotPaused {
        require(account != address(0));
        require(vestingGrants[account].isGranted);
        require(vestingGrants[account].isRevocable);
        require(vestingGrants[account].issuer == msg.sender, "Not an issuer"); // Only the original issuer can revoke a grant

        // Set the isGranted flag to false to prevent any further
        // actions on this grant from ever occurring
        vestingGrants[account].isGranted = false;

        // Get the remaining balance of the grant
        uint256 balanceDreams = vestingGrants[account].grantDreams -
            (vestingGrants[account].releasedDreams);
        emit Revoke(vestingGrants[account].issuer, account, balanceDreams);

        // If there is any balance left, return it to the issuer
        if (balanceDreams > 0) {
            tokenContract.transferFrom(
                address(this),
                msg.sender,
                balanceDreams
            );
        }
    }

    fallback() external {
        revert();
    }
}
