import pytest
from brownie import accounts, DAO, exceptions

min_buy_in = 1 * 10**18         # 1 eth 
period_fee = 0.1 * 10**18       # 0.1 eth
period_length = 2629800         # 1 month (365.25 / 12 * 24 * 60 * 60)
voting_reward = 0.01 * 10**18   # 0.01 eth (in internal points)
quorum = 50                     # 50%
vote_time = 604800               # 1 week (60 * 60 * 24 * 7)
one_eth = 1 * 10 ** 18


@pytest.fixture
def creator():
    return accounts[0]

@pytest.fixture
def mallory():
    return accounts[1]

@pytest.fixture
def dao(creator):
    return DAO.deploy(
        min_buy_in,
        period_fee,
        period_length,
        voting_reward,
        quorum,
        vote_time,
        {'from': creator, 'value': one_eth}
    )


##########
# DEPLOY #
##########

def test_deploy(creator):
    # Arrange
    value = 1*10**18
    
    # Act
    dao = DAO.deploy(
        min_buy_in,
        period_fee,
        period_length,
        voting_reward,
        quorum,
        vote_time,
        {'from': creator, 'value': value}
    )

    # Assert
    assert min_buy_in == dao.minBuyIn()
    assert period_fee == dao.periodFee()
    assert period_length == dao.periodLength()
    assert voting_reward == dao.votingReward()
    assert quorum == dao.quorum()
    assert vote_time == dao.voteTime()
    assert value == dao.getBalance()
    member_exists = dao.members(creator)[2]
    member_points = dao.members(creator)[0]
    member_last_payed_deadline = dao.members(creator)[1]
    assert member_exists == True
    assert member_points == value
    assert member_last_payed_deadline == dao.nextPeriodStart()
    assert dao.memberCount() == 1
    

############
# JOIN DAO #
############

def test_join_dao(dao, creator):
    # Arrange
    new_member = accounts[1]
    join_fee = 1 * 10**18
    initial_balance = dao.getBalance()
    initial_members = dao.memberCount()

    # Act 
    dao.requestToJoin(join_fee, {'from': new_member})
    dao.approveJoinRequest(new_member, {'from': creator})
    dao.join({'from': new_member, 'value': join_fee})

    # Assert
    member_exists = dao.members(new_member)[2]
    member_points = dao.members(new_member)[0]
    member_last_payed_deadline = dao.members(new_member)[1]
    assert member_exists == True
    assert member_points == join_fee
    assert member_last_payed_deadline == dao.nextPeriodStart()
    assert initial_balance + join_fee == dao.getBalance()
    assert initial_members + 1 == dao.memberCount()

def test_join_before_request(dao, mallory):
    with pytest.raises(exceptions.VirtualMachineError):
        dao.join({'from': mallory, 'value': min_buy_in})

def test_join_not_approved(dao, mallory):    
    dao.requestToJoin(min_buy_in, {'from': mallory})
    with pytest.raises(exceptions.VirtualMachineError): 
        dao.join({'from': mallory, 'value': min_buy_in})

def test_join_fee_too_low(dao, creator, mallory):
    correct_fee = min_buy_in
    low_fee = min_buy_in - 1
    with pytest.raises(exceptions.VirtualMachineError): 
        dao.requestToJoin(low_fee, {'from': mallory})
    dao.requestToJoin(correct_fee, {'from': mallory})
    dao.approveJoinRequest(mallory, {'from': creator})
    with pytest.raises(exceptions.VirtualMachineError): 
        dao.join({'from': mallory, 'value': low_fee})

def test_join_twice(dao, mallory):
    dao.requestToJoin(min_buy_in, {'from': mallory})
    with pytest.raises(exceptions.VirtualMachineError): 
        dao.requestToJoin(min_buy_in, {'from': mallory})
        


# TODO

# test only members
# test withdraw money


