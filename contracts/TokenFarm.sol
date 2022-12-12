// SPDX-License-Identifier: MIT

// Need to be able to do the following:
// 1) Stake tokens
// 2) Un-stake tokens
// 3) Issue token rewards
// 4) Add allowed tokens i.e. tokens allowed to be staked on platform
// 5) Get the value of the staked tokens on the platform

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract TokenFarm is Ownable {
    // mapping token address to staker address to amount staked by the staker
    // also using this mapping to check if token should be added to second mapping uniqueTokensStaked, by firstly checking if the staker has an amount greater than 0
    mapping(address => mapping(address => uint256)) public stakingBalance;
    // update this mapping using updateUniqueTokensStaked() function
    mapping(address => uint256) public uniqueTokensStaked;
    // map price feed address to token address, but then need a function to set the price feed contract => setPriceFeedContract()
    mapping(address => address) public tokenPriceFeedMapping;

    // This address array stores the list of allowed tokens to be staked.
    address[] public allowedTokens;
    // Address array of stakers which we can loop through and allocate rewards via issueTokens()
    address[] public stakers;

    // DAPP token stored here as global variable
    IERC20 public dappToken;

    // Using a constructor so that we create the reward token (DAPP token) right at the beginning of deploying this contract, and so that we have its address.
    // Store DAPP token as a global variable
    constructor(address _dappTokenAddress) {
        dappToken = IERC20(_dappTokenAddress);
    }

    // stake some amount of some token
    function stakeTokens(uint256 _amount, address _token) public {
        // What tokens can be staked? Any amount greater than zero
        // How much can they stake?
        // Here we are taking the amount (_amount) entered in the function argument and checking that it is greater than 0
        require(_amount > 0, "Amount staked must be greater than 0!");
        // Here we are taking the address of the token entered as an argument to this function (_token) and checking that it is allowed
        require(tokenIsAllowed(_token), "This token is not currently allowed!");
        // Wrap token in IERC20 which gives us the ABI also. We then transfer token from msg.sender (whomever calls stakeTokens()) to "this" tokenFarm contract.
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        // Now need to keep track of how much of a token user has sent, so need to create a mapping.
        // This mapping will map the staker address => token address => amount of token staked by user (Called stakingBalance, defined above)
        // Staking balance of this token, belonging to this staker, is now equal to the initial staking balance plus the new amount
        updateUniqueTokensStaked(msg.sender, _token);
        stakingBalance[_token][msg.sender] =
            stakingBalance[_token][msg.sender] +
            _amount;
        // Need to update stakers array (stakers[]) every time a new user stakes tokens
        // Create new function to update this stakers array, with arguments of msg.sender and _token, which is called here, but defined below

        if (uniqueTokensStaked[msg.sender] == 1) {
            stakers.push(msg.sender);
        }
    }

    function unstakeTokens(address _token) public {
        uint256 balance = stakingBalance[_token][msg.sender];
        require(balance > 0, "You do not have any token staked!");
        IERC20(_token).transfer(msg.sender, balance);
        stakingBalance[_token][msg.sender] = 0;
        // Note... is this vulnerable to re-entrancy attacks?
        uniqueTokensStaked[msg.sender] = uniqueTokensStaked[msg.sender] - 1;
        // TODO...remove user from stakers array if no tokens staked
    }

    // Need a list of the allowed tokens so we can check the inputted token against it i.e. is this token allowed?
    function tokenIsAllowed(address _token) public returns (bool) {
        // Going to use a list but a map is better!
        // Loop through the list to see if the token is contained within it.
        for (
            uint256 allowedTokensIndex = 0;
            allowedTokensIndex < allowedTokens.length;
            allowedTokensIndex++
        ) {
            if (allowedTokens[allowedTokensIndex] == _token) {
                return true;
            }
        }
        return false;
    }

    // Need a function to actually add allowed tokens to the allowedTokens array
    // Make this function on onlyOwner function because we only want the owner/admin to be able to add tokens
    function addAllowedTokens(address _token) public onlyOwner {
        allowedTokens.push(_token);
    }

    // This issueTokens() function is used to reward stakers who stake on the platform. It is based on the amount they have staked, and the underlying value of the specific token.
    // E.g. staker has deposited 100 ETH
    // Ratio is 1;1 i.e. for every ETH token staked, we give one DAPP token as a reward
    // What if 50 ETH and 50 DAI staked, and we want to give a reward of 1 Dapp token per 1 DAI token?
    // We would need to convert all the ETH into DAI to do this reward of 1:1
    // Only admin or owner can call this function.
    function issueTokens() public onlyOwner {
        // Need a list of stakers so we can loop through them in order to give out rewards
        // Can't loop through a mapping so we need an address array (stakers[] defined above)
        for (
            uint256 stakersIndex = 0;
            stakersIndex < stakers.length;
            stakersIndex++
        ) {
            // send staker a token reward based on their total value locked
            address recipient = stakers[stakersIndex];
            // need to know how much to send the recipient, so we need a function (getUserTotalValue) to determine this
            uint256 userTotalValue = getUserTotalValue(recipient);
            dappToken.transfer(recipient, userTotalValue);
        }
    }

    // Making this an internal fucntion so that only this contract can call it.
    function updateUniqueTokensStaked(address _user, address _token) internal {
        // Use if statement to ensure only new tokens are added if staker already has tokens
        if (stakingBalance[_user][_token] <= 0) {
            uniqueTokensStaked[_user] = uniqueTokensStaked[_user] + 1;
        }
    }

    // This function will determine the amount of rewards to issue the staker, based on the total value of all their tokens.
    function getUserTotalValue(address _user) public view returns (uint256) {
        uint256 totalValue = 0;
        require(uniqueTokensStaked[_user] > 0, "No tokens staked!");
        // need to loop through allowedTokens to see how much the user has for each of these allowed tokens.

        for (
            uint256 allowedTokensIndex = 0;
            allowedTokensIndex < allowedTokens.length;
            allowedTokensIndex++
        ) {
            totalValue =
                totalValue +
                getUserSingleTokenValue(
                    _user,
                    allowedTokens[allowedTokensIndex]
                );
        }
        return totalValue;
    }

    // this function is being called from getUserTotalValue() because we need to get the value of each token the user has, and then return its value to getUserTotalValue()
    // Get value of the amount of a token this user has staked.
    function getUserSingleTokenValue(address _user, address _token)
        public
        view
        returns (uint256)
    {
        // have token address so need to know which token this refers to i.e. need a mapping
        // once we know the token, we need to know the token value so need a price feed for the token => price * stakingBalance[_token][_user]
        // using an if here instead of require because we don't want the code to revert, we want it to keep running
        if (uniqueTokensStaked[_user] <= 0) {
            return 0;
        }
        // price * stakingBalance[_token][_user] => creating function to do this
        (uint256 price, uint256 decimals) = getTokenValue(_token);
        return ((stakingBalance[_token][_user] * price) / (10**decimals));
    }

    function getTokenValue(address _token)
        public
        view
        returns (uint256, uint256)
    {
        // need price info here in order to return the token value to getUserSingleTokenValue()
        // created mapping tokenPriceFeedMapping, and also function setPriceFeedContract() to map the token to the price feed
        address priceFeedAddress = tokenPriceFeedMapping[_token];
        // import chainlink aggregator via config, and this allows us to grab the specific price feed contract
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            priceFeedAddress
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // need to cast this because decimals returns an uint8
        uint256 decimals = uint256(priceFeed.decimals());
        // need to cast priceFeed because price returns an int256
        return (uint256(price), decimals);
    }

    // making this onlyOwner because we don't want anyone else to be able to set the price feed addresses
    function setPriceFeedContract(address _token, address _priceFeed)
        public
        onlyOwner
    {
        tokenPriceFeedMapping[_token] = _priceFeed;
    }
}
