from os import access
from brownie import accounts, DAO

min_buy_in = 1 * 10**18         # 1 eth 
period_fee = 0.1 * 10**18       # 0.1 eth
period_length = 2629800         # 1 month (365.25 / 12 * 24 * 60 * 60)
voting_reward = 0.01 * 10**18   # 0.01 eth (in internal points)
quorum = 50                     # 50%
voteTime = 604800               # 1 week (60 * 60 * 24 * 7)

def main():
    account = accounts[0]
    print(account)
    dao = DAO.deploy(
        min_buy_in,
        period_fee,
        period_length,
        voting_reward,
        quorum,
        voteTime,
        {'from': account}
    )
