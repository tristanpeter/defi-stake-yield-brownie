import pytest
from brownie import network, TokenFarm, DappToken, config, exceptions
from scripts.helpful_scripts import (
    LOCAL_BLOCKCHAIN_ENVIRONMENTS,
    INITIAL_PRICE_FEED_VALUE,
    get_account,
    get_contract,
)
from scripts.deploy import deploy_token_farm_and_dapp_token


def test_set_price_feed_contract():
    # as args, this takes token address and the price feed address
    # it is also an onlyOwner function
    # firstly want to check that we are on a local network

    # Arrange
    if network.show_active() not in LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        pytest.skip("Only for local testing!")
    account = get_account()
    non_owner_account = get_account(index=1)
    dapp_token, token_farm = deploy_token_farm_and_dapp_token()

    # Act
    price_feed_address = get_contract("dai_usd_price_feed")
    token_farm.setPriceFeedContract(
        dapp_token.address, price_feed_address, {"from": account}
    )

    # Assert
    assert token_farm.tokenPriceFeedMapping(dapp_token.address) == price_feed_address

    with pytest.raises(exceptions.VirtualMachineError):
        price_feed_address = get_contract("dai_usd_price_feed")
        token_farm.setPriceFeedContract(
            dapp_token.address, price_feed_address, {"from": non_owner_account}
        )


def test_stake_tokens(amount_staked):
    # Args = _token and _amount

    # Arrange
    if network.show_active() not in LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        pytest.skip("Only for local testing!")
    account = get_account()
    dapp_token, token_farm = deploy_token_farm_and_dapp_token()

    # ACT
    # First send some tokens to tokenFarm
    # Because we will be using an "amount_staked" a lot, turning it into a fixture
    # Define amount_staked in conf_test folder
    dapp_token.approve(token_farm.address, amount_staked, {"from": account})
    token_farm.stakeTokens(amount_staked, dapp_token.address, {"from": account})

    # Assert
    assert (
        token_farm.stakingBalance(dapp_token.address, account.address) == amount_staked
    )
    assert token_farm.uniqueTokensStaked(account.address) == 1
    assert token_farm.stakers(0) == account.address

    # returning these so they can be used in other tests
    return token_farm, dapp_token


# before we can test the issueTokens() function, we need to stake tokens first, so need to test stakeTokens() function first.
# amount of tokens issued depends on amount staked by staker
# also an onlyOwner function
# address of the recipient is found by looping through stakersIndex
# function calls getUserTotalValue() function, and then transfers DAPP token to recipient
def test_issue_tokens(amount_staked):
    # Arrange
    if network.show_active() not in LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        pytest.skip("Only for local testing!")
    account = get_account()
    token_farm, dapp_token = test_stake_tokens(amount_staked)
    starting_balance = dapp_token.balanceOf(account.address)
    # Act
    token_farm.issueTokens({"from": account})
    # Arrange
    # we are staking 1 dapp_token == in price to 1 ETH
    # soo... we should get 2,000 dapp tokens in reward
    # since the price of eth is $2,000
    assert (
        dapp_token.balanceOf(account.address)
        == starting_balance + INITIAL_PRICE_FEED_VALUE
    )
