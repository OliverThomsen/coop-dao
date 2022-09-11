import pytest
from brownie import accounts, DAO, exceptions, chain, reverts

buy_in = 1 * 10**18             # 1 eth 
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
        buy_in,
        period_fee,
        period_length,
        voting_reward,
        quorum,
        vote_time,
        {'from': creator, 'value': one_eth}
    )



@pytest.fixture
def dao_with_3_members(dao):
    # join account 1
    dao.requestToJoin({'from': accounts[1]})
    dao.approveJoinRequest(accounts[1], {'from': accounts[0]})
    dao.join({'from': accounts[1], 'value': buy_in})
    # join account 2
    dao.requestToJoin({'from': accounts[2]})
    dao.approveJoinRequest(accounts[2], {'from': accounts[0]})
    dao.join({'from': accounts[2], 'value': buy_in})
    return dao


##########
# DEPLOY #
##########

def test_deploy(creator):
    # Arrange
    value = 1*10**18
    
    # Act
    dao = DAO.deploy(
        buy_in,
        period_fee,
        period_length,
        voting_reward,
        quorum,
        vote_time,
        {'from': creator, 'value': value}
    )

    # Assert
    assert buy_in == dao.buyInFee()
    assert period_fee == dao.periodFee()
    assert period_length == dao.periodLength()
    assert voting_reward == dao.votingReward()
    assert quorum == dao.quorum()
    assert vote_time == dao.voteTime()
    assert value == dao.availableFunds()
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
    initial_balance = dao.availableFunds()
    initial_members = dao.memberCount()

    # Act 
    dao.requestToJoin({'from': new_member})
    dao.approveJoinRequest(new_member, {'from': creator})
    dao.join({'from': new_member, 'value': join_fee})

    # Assert
    member_exists = dao.members(new_member)[2]
    member_points = dao.members(new_member)[0]
    member_last_payed_deadline = dao.members(new_member)[1]
    assert member_exists == True
    assert member_points == join_fee
    assert member_last_payed_deadline == dao.nextPeriodStart()
    assert initial_balance + join_fee == dao.availableFunds()
    assert initial_members + 1 == dao.memberCount()
    assert True == dao.memberIsActive(new_member)

def test_join_before_request(dao, mallory):
    with pytest.raises(exceptions.VirtualMachineError):
        dao.join({'from': mallory, 'value': buy_in})

def test_join_not_approved(dao, mallory):    
    dao.requestToJoin({'from': mallory})
    with pytest.raises(exceptions.VirtualMachineError): 
        dao.join({'from': mallory, 'value': buy_in})

def test_join_fee_too_low(dao, creator, mallory):
    low_fee = buy_in - 1
    dao.requestToJoin({'from': mallory})
    dao.approveJoinRequest(mallory, {'from': creator})
    with pytest.raises(exceptions.VirtualMachineError): 
        dao.join({'from': mallory, 'value': low_fee})

def test_join_twice(dao, mallory):
    dao.requestToJoin({'from': mallory})
    with pytest.raises(exceptions.VirtualMachineError): 
        dao.requestToJoin({'from': mallory})
        

#####################
# SPENDING PROPOSAL #
#####################

def test_propose_spending_not_member(dao):
    with reverts("Only members can call this function"): 
        dao.proposeSpending(0.1 * 10**18, accounts[3], "spending 1", {'from': accounts[3]})


def test_propose_spending_not_enough_funds(dao):
    with reverts("Not enough funds"):
        dao.proposeSpending(2 * 10**18, accounts[3], "spending 1", {'from': accounts[0]})

def test_propose_spending(dao):
    # Arange 
    amount = 0.1 * 10**18
    name = "spending 1"
    recipient = accounts[1]
    proposal_count_before = dao.spendingProposalCount()
    id = proposal_count_before
    
    # Act
    dao.proposeSpending(amount, recipient, name, {'from': accounts[0]})
    proposal = dao.spendingProposals(id)
    initial_vote = proposal[7]
    final_vote = proposal[8]

    # Assert
    assert proposal_count_before + 1 == dao.spendingProposalCount()
    assert proposal[0] == id
    assert proposal[1] == name
    assert proposal[2] == amount
    assert proposal[3] == recipient
    assert proposal[4] == True # proposal exists
    assert proposal[5] == False # proposal withdrawn
    assert proposal[6] == False # proposal has reverved funds

    assert initial_vote[1] == accounts[0] # proposer 
    assert initial_vote[3] == 0 # yes votes 
    assert initial_vote[4] == 0 # no votes 
    assert initial_vote[5] == 0 # number if members voted

    assert final_vote[1] == accounts[0] # proposer 
    assert final_vote[2] == 0 # end time (because vote not begun) 
    assert final_vote[3] == 0 # yes votes 
    assert final_vote[4] == 0 # no votes 
    assert final_vote[4] == 0 # number if members voted


def test_spending_proposal_flow_success(dao):
    # Arrange 
    amount = 0.1 * 10**18
    name = "Spending Test"
    recipient = accounts[1]
    tx = dao.proposeSpending(amount, recipient, name, {'from': accounts[0]})
    id = tx.return_value

    # Inital voting round
    tx = dao.voteSpendingProposal(id, True, {'from': accounts[0]})
    tx.wait(1)
    assert dao.spendingProposalPassed(id)[0] == False
    chain.sleep(vote_time + 10)
    chain.mine(1)
    assert dao.spendingProposalPassed(id)[0] == True
    assert dao.canWithdrawProposal(id, {'from': recipient})[0] == False
    with reverts("Not enough members participated in the vote"):
        dao.withdraw(id, {'from': recipient})

    # Final voting round no pass
    dao.voteReleaseFundsSpendingProposal(id, False, {'from': accounts[0]})
    chain.sleep(vote_time + 10)
    chain.mine(1)
    assert dao.spendingProposalFundsReleased(id)[0] == False
    with reverts("Vote did not pass"):
        dao.withdraw(id, {'from': recipient})

    # Do final voting round again pass
    dao.voteReleaseFundsSpendingProposal(id, True, {'from': accounts[0]})
    assert dao.spendingProposalFundsReleased(id)[0] == False
    chain.sleep(vote_time + 10)
    chain.mine(1)
    assert dao.spendingProposalFundsReleased(id)[0] == True

    # Withdraw
    prevBalanceDAO = dao.balance()
    prevBalanceReciever = recipient.balance()
    # assert dao.canWithdrawProposal(id, {'from': recipient})[0] == True # fails during --coverage
    dao.reserveFunds(id, {'from': recipient}) # todo make seperate test for this
    dao.withdraw(id, {'from': recipient})
    assert dao.canWithdrawProposal(id, {'from': recipient})[0] == False
    with reverts("You have already withdrawn your funds"):
        dao.withdraw(id, {'from': recipient})
    assert dao.balance() == prevBalanceDAO - amount
    assert recipient.balance() == prevBalanceReciever + amount

####################
# Governace update #
####################

def test_governance_update(dao_with_3_members):
    new_quorum = 60
    new_buyInFee = 0.5 * 10**18
    new_voteTime = 60 * 60 * 24 # one day
    new_votingReward = 0.1 * 10**18
    new_periodFee = 0.2 * 10**18
    new_periodLength = 60 * 60 * 24 * 7 # one week
    # Propose gov update
    tx = dao_with_3_members.proposeGovernanceUpdate(
        new_quorum,
        new_buyInFee,
        new_voteTime,
        new_votingReward,
        new_periodFee,
        new_periodLength,
        {'from': accounts[0]}
    )
    id = tx.return_value

    dao_with_3_members.voteGovProposal(id, True, {'from': accounts[1]})
    dao_with_3_members.voteGovProposal(id, True, {'from': accounts[2]})
    chain.sleep(vote_time + 10)
    chain.mine(1)
    assert dao_with_3_members.govProposalPassed(id)[0] == True
    dao_with_3_members.implementGovProposal(id)

    assert dao_with_3_members.quorum() == new_quorum
    assert dao_with_3_members.buyInFee() == new_buyInFee
    assert dao_with_3_members.voteTime() == new_voteTime
    assert dao_with_3_members.periodFee() == new_periodFee
    assert dao_with_3_members.periodLength() == new_periodLength

##############    
# Period Fee #
##############

def test_pay_period_fee(dao):
    chain.sleep(2 * period_length + 100)
    chain.mine(1)
    print((dao.nextPeriodStart() - dao.members(accounts[0])[1]) / period_length)
    print('now', chain.time())
    print('next', dao.nextPeriodStart())
    print('payed', dao.members(accounts[0])[1])
    with reverts('Only active members can call this function'):
        dao.proposeSpending(1000, accounts[1], 'Test', {'from': accounts[0]})
    tx = dao.payPeriodFee({'from': accounts[0], 'value': 2 * period_fee})
    print(tx.events)
    dao.proposeSpending(1000, accounts[1], 'Test', {'from': accounts[0]})

def test_fund(dao):
    prev_balance = dao.balance() 
    prev_points = dao.members(accounts[0])[0]
    value =  5 * 10**18
    
    with reverts("Only members can call this function"):
        dao.fund({'from': accounts[1], 'value': value}).wait(1)    
    dao.fund({'from': accounts[0], 'value': value}).wait(1)
    new_points = dao.members(accounts[0])[0]

    assert prev_balance + value == dao.balance()
    assert prev_points + value == new_points






