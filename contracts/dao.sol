// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Oliver Elleman Thomsen
 * 
 */
contract DAO {

    // Governance variables
    uint8 public quorum; // minimum percentage of active members required to participate in a vote
    uint public buyInFee; // minimum fee to join the DAO
    uint public voteTime; // amount of time in seconds you have, to vote on a proposal
    uint public votingReward; // amount of points a member is rewarded for participating in a vote
    uint public periodFee; // fee you must pay every period to stay a member
    uint public periodLength; // amount of time between mandatory payments

    // Members
    uint public memberCount = 0; // number of members that have joined the DAO
    mapping(address => Member) public members; // map of member ojects indexed by wallet address
    mapping(uint => uint) public activeMembersInPeriod; // Keeps track of how many active members there is in a period (timestamp => activeMembers)
   
    // Proposals
    uint public reservedFunds = 0; // total funds reseved for passed spending proposals
    uint public spendingProposalCount = 0; // total number of spending proposals
    uint public govProposalCount = 0; // total number of governance proposals
    uint private proposalCount = 0; // total instances of the Vote struct
    mapping(uint => SpendingProposal) public spendingProposals; // spending proposals indexed by spendingProposalCount
    mapping(uint => GovProposal) public govProposals; // governance proposals indexed by govProposalCount
    mapping(address => mapping(uint => bool)) public memberVotedOnProposal; // tells if a member voted on a proposal (memberAddress => proposalId => hasVoted) 

    // Join requests
    mapping(address => JoinRequest) public joinRequests; // join requests indexed by the requester wallet address
    mapping(address => mapping(address => bool)) public memberApprovedRequest; // tells if a member has approved a join request (memberAddress => requesterAddress => hasApproved)

    // Events
    event NewJoinRequest(address from);
    event NewMember(address member);
    event NewSpendingProposal(SpendingProposal spendingProposal);
    event FinalizeSpendingProposal(SpendingProposal spendingProposal);
    event NewGovProposal(GovProposal govProposal);
    event GovernanceUpdate(GovProposal govProposal);

    struct Member {
        uint points; 
        uint lastPayedPeriod;
        bool exists;
    }

    struct SpendingProposal {
        uint id; // derived form incrementing spendingProposalCount
        string name; // name or description for proposal 
        uint amount; // amount of funds to transfer to recipient 
        address payable recipient; // recieving address for the amount of funds
        bool exists; // always true once created otherwise false
        bool withdrawn; // true after recipient has withdrawn amount
        bool hasReservedFunds; // true if recipient has reserved the funds for withdrawing later
        Vote initialVote; // used for voting on whether or not to accept with the proposal
        Vote finalVote; // used for voting on whether or not to release the funds to the recipient
    }

    struct GovProposal {
        uint id; // derived from incrementing govProposalCount
        uint8 quorum;
        uint buyInFee;
        uint voteTime;
        uint votingReward;
        uint periodFee;
        uint periodLength;
        bool exists; // always true once created otherwise false
        bool implemented; // true after the proposal has been implimented by a member
        Vote vote; // used for voting on wheter or not to implement the proposal
    }

    struct Vote {
        uint id; // derived from incrementing proposalCount
        address proposer; // the creater of the proposal 
        uint endTime; // epoch timestamp of when it is not longer possible to vote on proposal
        uint yesVotes; // total number of votes FOR
        uint noVotes; // total number of votes AGAINST
        uint numMembersVoted; // number of members who have participated in the vote
    }

    struct JoinRequest {
        address requester; // wallet address of the person requesting to join
        bool sent; // true after the request is created 
        uint approvals; // number of members who have approved the request
    }

    modifier onlyMembers {
        require(members[msg.sender].exists == true, "Only members can call this function");
        _;
    }

    modifier onlyActiveMembers {
        require(members[msg.sender].exists == true, "Only members can call this function");
        require(memberIsActive(msg.sender) == true, "Only active members can call this function");
        _;
    }

    modifier onlyNonMembers {
        require(members[msg.sender].exists == false, "Only non members can call this function");
        _;
    }


    constructor(uint _buyInFee, uint _periodFee, uint _periodLength,  uint _votingReward, uint8 _quorum, uint _voteTime) payable {
        require(_quorum > 0 && _quorum <= 100, "Quorum must be between 0 and 100");
        buyInFee = _buyInFee;
        periodFee = _periodFee;
        quorum = _quorum;
        voteTime = _voteTime;
        votingReward = _votingReward;
        periodLength = _periodLength;

        uint nextPeriod = nextPeriodStart();
        members[msg.sender] = Member({
            points: msg.value,
            lastPayedPeriod: nextPeriod,
            exists: true
        });
        memberCount += 1;
        // Set as active member in current period and next period
        activeMembersInPeriod[nextPeriod - periodLength] += 1;
        activeMembersInPeriod[nextPeriod] += 1;

    }

    // Can be used if a memebr wishes to fund the DAO beyond the required periodic fee
    function fund() external payable onlyMembers {
        members[msg.sender].points += msg.value;
    }

    // Must be called once every period (before nextPeriodStart) to stay an active member
    function payPeriodFee() external payable onlyMembers {
        uint nextPeriod = nextPeriodStart();
        uint periodsToPay = (nextPeriod - members[msg.sender].lastPayedPeriod) / periodLength;
        require(periodsToPay > 0, "You have already payed for this period");
        require(msg.value == periodFee * periodsToPay, "Value does not equal required period fee");
        members[msg.sender].points += msg.value;  // get points equivalent to amount of ETH
        members[msg.sender].lastPayedPeriod = nextPeriod;
        activeMembersInPeriod[nextPeriod] += 1;
    }

    // Send a request to join the DAO, other members must then approve the request  
    function requestToJoin() external onlyNonMembers {
        require(joinRequests[msg.sender].sent == false, "You already sent a join request");
        joinRequests[msg.sender] = JoinRequest({
            requester: msg.sender,
            sent: true,
            approvals: 0 
        });
        emit NewJoinRequest(msg.sender);
    }

    // Approve a request to join the DAO
    function approveJoinRequest(address requester) external onlyActiveMembers {
        require(joinRequests[requester].sent == true, "This address has not sent a join request");
        require(memberApprovedRequest[msg.sender][requester] == false, "You have already approved this join request");
        memberApprovedRequest[msg.sender][requester] = true;
        joinRequests[requester].approvals += 1;
    }

    // Join the DAO when more than the quorum percentage of the active members have approve your join request
    function join() payable external onlyNonMembers {
        require(joinRequests[msg.sender].sent == true, "You need to send a join request before you can join");
        uint currentPeriod = nextPeriodStart() - periodLength;
        uint activeMembers = activeMembersInPeriod[currentPeriod];
        require(joinRequests[msg.sender].approvals * 100 > quorum * activeMembers, "Your request to join has not been approved by enough active members");
        require(msg.value >= buyInFee, "Buy in value too low");
        delete joinRequests[msg.sender]; // delete join request (sets all values in the struct to their default value)
        uint nextPeriod = nextPeriodStart();
        members[msg.sender] = Member({
            points: msg.value,
            lastPayedPeriod: nextPeriod,
            exists: true
        });
        memberCount += 1;
        // Set as active member in current period and next period
        activeMembersInPeriod[nextPeriod - periodLength] += 1;
        activeMembersInPeriod[nextPeriod] += 1;
        emit NewMember(msg.sender);
    }

    // Create a proposal to spend money
    function proposeSpending(uint amount, address payable recipient, string memory name) external onlyActiveMembers returns(uint){
        require(availableFunds() >= amount, "Not enough funds");
        uint id = spendingProposalCount;
        spendingProposals[id] = SpendingProposal({
            id: id,
            name: name,
            amount: amount,
            recipient: recipient,
            exists: true,
            withdrawn: false,
            hasReservedFunds: false,
            initialVote: createVote(block.timestamp + voteTime),
            finalVote: createVote(0) // endTime is 0 because voting has not started yet
        });
        spendingProposalCount++;
        emit NewSpendingProposal(spendingProposals[id]);
        return id;
    }

    // Propose an update to change governance variables
    function proposeGovernanceUpdate(uint8 _quorum, uint _buyInFee, uint _voteTime,  uint _votingReward, uint _periodFee, uint _periodLength) external onlyActiveMembers returns(uint) {
        uint id = govProposalCount;
        govProposals[id] = GovProposal({
            id: id,
            quorum: _quorum,
            buyInFee: _buyInFee,
            voteTime: _voteTime,
            votingReward: _votingReward,
            periodFee: _periodFee,
            periodLength: _periodLength,
            exists: true,
            implemented: false,
            vote: createVote(block.timestamp + voteTime)
        });
        govProposalCount++;
        emit NewGovProposal(govProposals[id]);
        return id;
    }

    function createVote(uint endTime) internal onlyActiveMembers returns(Vote memory){
        Vote memory vote = Vote({
            id: proposalCount,
            proposer: msg.sender,
            endTime: endTime,
            yesVotes: 0,
            noVotes: 0,
            numMembersVoted: 0
        });
        proposalCount += 1;
        return vote;
    }

    // Vote on accepting a spending proposal
    function voteSpendingProposal(uint id, bool votingYes) external onlyActiveMembers {
        require(id < spendingProposalCount, "No spending proposal exists with this id");
        Vote storage vote = spendingProposals[id].initialVote;
        submitVote(vote, votingYes);
    }

    // Vote on releasing funds for a spending proposal
    function voteReleaseFundsSpendingProposal(uint proposalId, bool votingYes) external onlyActiveMembers {
        require(proposalId < spendingProposalCount, "No spending proposal exists with this id");
        Vote storage initialVote = spendingProposals[proposalId].initialVote;
        (bool initialVotePassed,) = voteHasPassed(initialVote);
        require(initialVotePassed == true, "Initail vote has not passed");
        Vote storage finalVote = spendingProposals[proposalId].finalVote;
        // If voting period has not begun, begin voting period
        if (finalVote.endTime == 0) {
            finalVote.endTime = block.timestamp + voteTime;
            emit FinalizeSpendingProposal(spendingProposals[proposalId]);
        }
        // If Voting period ended, and vote not passed, restart voting period
        (bool finalVotePassed,) = voteHasPassed(finalVote);
        if(finalVote.endTime <= block.timestamp && !finalVotePassed) {
            spendingProposals[proposalId].finalVote = createVote(block.timestamp + voteTime);
            emit FinalizeSpendingProposal(spendingProposals[proposalId]);
        }
        submitVote(finalVote, votingYes);
    }

    // Vote on governance proposal
    function voteGovProposal(uint id, bool votingYes) external onlyActiveMembers {
        require(id < govProposalCount, "No governance proposal exists with this id");
        submitVote(govProposals[id].vote, votingYes);
    }

    function submitVote(Vote storage vote, bool votingYes) internal onlyActiveMembers {
        require(vote.endTime > block.timestamp, "Voting period has ended");
        require(memberVotedOnProposal[msg.sender][vote.id] == false, "You have already voted once");
        memberVotedOnProposal[msg.sender][vote.id] = true;
        uint votingPower = sqrt(members[msg.sender].points);
        if (votingYes) {
            vote.yesVotes += votingPower;
        } else {
            vote.noVotes += votingPower;
        }
        vote.numMembersVoted += 1;
        // Award points for voting, if not own vote
        if (vote.proposer != msg.sender) {
            members[msg.sender].points += votingReward;
        }
    }

    // Withdraw funds for a spending proposal
    function withdraw(uint proposalId) external {
        (bool canWithdraw, string memory errorMessage) = canWithdraw(proposalId);
        require(canWithdraw == true, errorMessage);
        require(enoughFundsForProposal(proposalId) == true, "Contract balnce too low. Use reserveFunds if you are the proposal recipient");
        SpendingProposal storage proposal = spendingProposals[proposalId];

        // Clear reserved funds for proposal
        if (proposal.hasReservedFunds) {
            proposal.hasReservedFunds = false;
            reservedFunds -= proposal.amount;
        }
        // updating guard varaible (withdrawn) before transfering to prevent reentrancy attack
        proposal.withdrawn = true;
        payable(msg.sender).transfer(proposal.amount);
    }

    // Call this funciton before withdraw to check if there are enough funds, to avoid paying gas for a failed transaction
    function enoughFundsForProposal(uint proposalId) public view returns(bool){
        SpendingProposal storage proposal = spendingProposals[proposalId];
        if (proposal.hasReservedFunds) {
            return proposal.amount <= address(this).balance;
        }
        return proposal.amount <= availableFunds();    
    }

    // Call this function if there are not enough funds to withdraw the proposal amount
    function reserveFunds(uint proposalId) public {
        (bool canWithdraw, string memory errorMessage) = canWithdraw(proposalId);
        require(canWithdraw == true, errorMessage);
        SpendingProposal storage proposal = spendingProposals[proposalId];
        require(proposal.hasReservedFunds == false, "You have already reserved your funds");
        proposal.hasReservedFunds = true;
        reservedFunds += proposal.amount;
    }

    function canWithdraw(uint proposalId) internal view returns(bool, string memory) {
        if (proposalId >= spendingProposalCount) {
            return (false, "No spending proposal exists with this id");
        }
        SpendingProposal storage proposal = spendingProposals[proposalId];
        if (proposal.recipient != msg.sender) {
            return (false, "You are not the recipient");
        }
        if (proposal.withdrawn == true) {
            return (false, "You have already withdrawn your funds");
        }
        (bool passed, string memory message) = voteHasPassed(proposal.finalVote);
        if (passed == false) {
            return (false, message);
        }
        return (true, "Proposal amount can be withdrawn");
    }

    function spendingProposalPassed(uint id) external view returns(bool, string memory) {
        require(id < spendingProposalCount, "No spending proposal exists with this id");
        return voteHasPassed(spendingProposals[id].initialVote);
    }

    function spendingProposalFundsReleased(uint id)  external view returns(bool, string memory) {
        require(id < spendingProposalCount, "No spending proposal exists with this id");
        return voteHasPassed(spendingProposals[id].finalVote);
    }

    function govProposalPassed(uint id) external view returns(bool, string memory) {
        return voteHasPassed(govProposals[id].vote);
    }

    function voteHasPassed(Vote memory vote) internal view returns(bool, string memory) {
        if (vote.endTime > block.timestamp) {
            return (false, "Voting peroid is not over");
        }
        uint activeMembers = activeMembersInPeriod[nextPeriodStart() - periodLength];
        if (vote.numMembersVoted  * 100 < quorum * activeMembers) {
            return (false, "Not enough members participated in the vote");
        }
        if (vote.yesVotes <= vote.noVotes) {
            return (false, "Vote did not pass");
        }
        return (true, "Vote passed");
    }

    // Implement a governace proposal once it has passed the vote
    function implementGovProposal(uint id) external onlyActiveMembers {
        require(id < govProposalCount, "No governance proposal exists with this id");
        GovProposal storage proposal = govProposals[id];
        require(proposal.implemented == false, "Governance proposal already implimented");
        (bool passed, string memory message) = voteHasPassed(proposal.vote);
        require(passed == true, message);
        proposal.implemented = true;
        quorum = proposal.quorum;
        buyInFee = proposal.buyInFee;
        voteTime = proposal.voteTime;
        votingReward = proposal.votingReward;
        periodFee = proposal.periodFee;
        periodLength = proposal.periodLength;
        emit GovernanceUpdate(proposal);
    }


    function memberIsActive(address memberAddress) public view returns(bool) {
        return members[memberAddress].lastPayedPeriod + periodLength > block.timestamp; 
    }

    // Returns the epoch timestamp of when the next period starts
    function nextPeriodStart() public view returns(uint) {
        uint timeSinceLastPeriod = block.timestamp % periodLength;
        if (timeSinceLastPeriod == 0) {
            return block.timestamp;
        } else {
            return block.timestamp + periodLength - timeSinceLastPeriod;
        }
    }

    function availableFunds() public view returns(uint) {
        return address(this).balance - reservedFunds;
    }

    // Simple square root function from https://github.com/OpenZeppelin/openzeppelin-contracts/pull/3242
    // Uses a lot of gas for big ints, but the implementation is very simple.
    // Could be replaced with the very long but more efficient version from open zeppelin
    function sqrt(uint x) internal pure returns (uint y) {
        uint z = x / 2 + x % 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
    
}
