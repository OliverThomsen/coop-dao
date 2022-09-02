// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Oliver Elleman Thomsen
 * 
 */
contract DAO {

    //todo
    uint balance;

    // Governance attributes
    uint8 public quorum; // minimum percentage of active members required to participate in a vote
    uint public buyInFee; // minimum fee to join the DAO
    uint public voteTime; // amount of time in seconds you have, to vote on a proposal
    uint public votingReward; // amount of points a member is rewarded for participating in a vote
    uint public periodFee; // fee you must pay every period to stay a member
    uint public periodLength; // Amount of time between mandatory payments

    // Members
    uint public memberCount = 0; // number of members that have joined the DAO
    mapping(address => Member) public members; // map of member ojects by wallet addresses
    mapping(uint => uint) public activeMembersInPeriod; // (timestamp => activeMembers) number of active members for every period
   
    // Proposals
    uint public proposalCount = 0;
    mapping(uint => Proposal) public proposals; // Proposals indexed by incremental ids
    mapping(address => mapping(uint => bool)) public memberVotedOnProposal; // (memberAddress => proposalId => hasVoted) 
    mapping(address => uint) public contractorBalances; // 

    // Join requests
    mapping(address => JoinRequest) public joinRequests; // JoinRequests indexed by the requester wallet address
    mapping(address => mapping(address => bool)) public memberApprovedRequest; // (memberAddress => requesterAddress => hasApproved)

    // Events
    event NewJoinRequest(address from);
    event NewMember(address member);
    event NewProposal(uint proposalId, Proposal proposal);
    event ProposalRealized(uint proposalId, Proposal proposal);

    struct Member {
        uint points;
        uint lastPayedPeriod;
        bool exists;
    }

    struct Proposal {
        address proposer; // the creater of the proposal 
        uint endTime; // epoch timestamp of when it is not longer possible to vote on proposal
        uint yesVotes; // total number of YES votes on proposal, weighted by square root of member points
        uint noVotes; // total number of NO votes on proposal, weighted by square root of member points
        uint numMembersVoted; // number of members who have voted on proposal
        bool realized; // true if proposal is realized
        SpendingProposal spendingProposal; // spending proposal object if applicable
        GovProposal govProposal; // govenance proposal object if applicable
    }

    struct SpendingProposal {
        string name; // name or description of proposal 
        uint amount; // amount of funds to transfer to recipient 
        address payable recipient; // recieving address of the amount of funds
        bool exists; // always true once created otherwise false
    }

    struct GovProposal {
        uint8 quorum;
        uint buyInFee;
        uint voteTime;
        uint votingReward;
        uint periodFee;
        uint periodLength;
        bool exists;
    }

    struct JoinRequest {
        address requester;
        bool send;
        uint buyIn;
        uint approvals;
    }


    modifier onlyMembers {
        require(members[msg.sender].exists == true, "Only members can call this function");
        _;
    }

    modifier onlyActiveMembers {
        require(members[msg.sender].exists == true, "Only members can call this function");
        require(isActive(msg.sender) == true, "Only active members can call this function");
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

    function fund() external payable onlyMembers {
        members[msg.sender].points += msg.value;
    }

    // Send a request to join the DAO 
    // Other members must accept the request  
    function requestToJoin(uint _buyIn) external onlyNonMembers {
        require(joinRequests[msg.sender].send == false, "You already send a join request");
        require(_buyIn >= buyInFee, "Buy in value too low");
        joinRequests[msg.sender] = JoinRequest({
            requester: msg.sender,
            send: true,
            buyIn: _buyIn,
            approvals: 0 
        });
        emit NewJoinRequest(msg.sender);
    }


    // Approve a request to join the DAO
    // When a request is approved, the requester can call the join function to officially join the DAO
    // TODO: Quadratic voting on new members?
    function approveJoinRequest(address requester) external onlyActiveMembers {
        require(joinRequests[requester].send == true, "This address has not send a join request");
        require(memberApprovedRequest[msg.sender][requester] == false, "You have already approved this join request");
        memberApprovedRequest[msg.sender][requester] = true;
        joinRequests[requester].approvals += 1;
    }

    // msg.value is in the unit Wei. 1 Ether = 10^18 Wei
    function join() payable external onlyNonMembers {
        require(joinRequests[msg.sender].send == true, "You need to send a join request before you can join");
        uint currentPeriod = nextPeriodStart() - periodLength;
        uint activeMembers = activeMembersInPeriod[currentPeriod];
        require(joinRequests[msg.sender].approvals * 100 >= quorum * activeMembers, "Your request to join has not been approved by enough active members");
        require(msg.value == joinRequests[msg.sender].buyIn, "Value must be the same as buyIn in the joinRequest");
        delete joinRequests[msg.sender]; // delete sets all values in the srtuct to their default value
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


    // Propose to spend money
    function ProposeSpending(uint amount, address payable recipient, string memory name) external onlyActiveMembers {
        require(address(this).balance >= amount, "Not enough funds");
        SpendingProposal memory spendingProposal = SpendingProposal({
            name: name,
            amount: amount,
            recipient: recipient,
            exists: true

        });
        GovProposal memory emptyGovProposal;
        createProposal(spendingProposal, emptyGovProposal);
    }

    // propose vote to change global params
    function ProposeConfigurationUpdate(uint8 _quorum, uint _buyInFee, uint _voteTime,  uint _votingReward, uint _periodFee, uint _periodLength) external onlyActiveMembers {
        GovProposal memory govProposal = GovProposal({
            quorum: _quorum,
            buyInFee: _buyInFee,
            voteTime: _voteTime,
            votingReward: _votingReward,
            periodFee: _periodFee,
            periodLength: _periodLength,
            exists: true
        });
        SpendingProposal memory emptySpendingProposal;
        createProposal(emptySpendingProposal, govProposal);
    }

    function createProposal(SpendingProposal memory sp, GovProposal memory cp) internal onlyActiveMembers {
        proposals[proposalCount] = Proposal({
            proposer: msg.sender,
            endTime: block.timestamp + voteTime,
            yesVotes: 0,
            noVotes: 0,
            numMembersVoted: 0,
            realized: false,
            spendingProposal: sp,
            govProposal: cp
        });
        emit NewProposal(proposalCount, proposals[proposalCount]);
        proposalCount += 1;

    }

    // Vote on a proposal and get rewarded with points
    // maybe proof 
    function vote(uint proposalId, bool votingYes) external onlyActiveMembers {
        require(proposalId < proposalCount, "No proposal exists with this id");
        require(proposals[proposalId].endTime > block.timestamp, "Voting period has ended");
        require(memberVotedOnProposal[msg.sender][proposalId] == false, "You have already voted once");
        require(proposals[proposalId].proposer != msg.sender, "You cannot vote on your own proposal");
        memberVotedOnProposal[msg.sender][proposalId] = true;
        // Quadratic voting: take square root of points to make it harder to buy power
        uint weightedVote = sqrt(members[msg.sender].points);
        if (votingYes) {
            proposals[proposalId].yesVotes = weightedVote;
        } else {
            proposals[proposalId].noVotes = weightedVote;
        }
        proposals[proposalId].numMembersVoted += 1;
        // Award points for voting, if not own proposal
        if (proposals[proposalId].proposer != msg.sender) {
            members[msg.sender].points += votingReward;
        }
    }

    function payPeriodFee() external payable onlyMembers {
        uint nextPeriod = nextPeriodStart();
        uint periodsToPay = (nextPeriod - members[msg.sender].lastPayedPeriod) / periodLength;
        require(periodsToPay == 0, "You have already payed for this period");
        require(msg.value == periodFee * periodsToPay, "Value does not equal required period fee");
        members[msg.sender].points += msg.value;  // get points equivalent to amount of ETH
        members[msg.sender].lastPayedPeriod = nextPeriodStart();
        activeMembersInPeriod[nextPeriod] += 1;
    }


    // todo: get points for this ...
    // maybe call by conrtactor - but then implement voting round two - avoid bribing smallest memeber to releaze funds
    // second vote emits event 
    function realizeProposal(uint id) external onlyActiveMembers {
        require(id < proposalCount, "No proposal exists with this id");
        require(proposals[id].endTime <= block.timestamp, "Voting peroid is not over");
        require(proposals[id].realized == false, "Proposal already realized");
        uint activeMembers = activeMembersInPeriod[nextPeriodStart() - periodLength];
        require((proposals[id].numMembersVoted  * 100) / activeMembers >= quorum, "Not enough members participated in the vote"); // multiply with 100 before dividing to avoid rounding error
        require(proposals[id].yesVotes >= proposals[id].noVotes, "Proposal did not pass vote");
    
        SpendingProposal storage spendingProposal = proposals[id].spendingProposal;
        if (spendingProposal.exists) {
            require(spendingProposal.amount <= address(this).balance, "Not enough funds to complete proposal");
            contractorBalances[spendingProposal.recipient] += spendingProposal.amount;
        }

        GovProposal storage govProposal = proposals[id].govProposal;
        if (govProposal.exists) {
            updateConfigurations(govProposal);
        }
        
        proposals[id].realized = true;
        emit ProposalRealized(id, proposals[id]);
        // todo update balance
    }

    // todo
    function isRealized(uint proposalId) public view returns(bool) {

    }

    function updateConfigurations(GovProposal storage proposal) internal onlyActiveMembers {
        quorum = proposal.quorum;
        buyInFee = proposal.buyInFee;
        voteTime = proposal.voteTime;
        votingReward = proposal.votingReward;
        periodFee = proposal.periodFee;
        periodLength = proposal.periodLength;
    }

    // Returns time left on proposal in seconds
    function getTimeLeftOnProposal(uint id) public view returns(uint) {
        require(id < proposalCount, "No proposal exists with this id");
        uint endTime = proposals[id].endTime;
        return endTime - block.timestamp;
    } 


    function withdraw() external {
        uint amount = contractorBalances[msg.sender];
        require(amount > 0, "You have no funds to withdraw");
        // updating internal accounts before transfering to prevent reentrancy attack
        contractorBalances[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }

    function isActive(address memberAddress) internal view returns(bool) {
        return members[memberAddress].lastPayedPeriod + periodLength > block.timestamp; 
    }

    function nextPeriodStart() public view returns(uint) {
        uint timeSinceLastPayment = block.timestamp % periodLength;
        if (timeSinceLastPayment == 0) {
            return block.timestamp;
        } else {
            return block.timestamp + periodLength - timeSinceLastPayment;
        }
    }

    function getBalance() external view returns(uint) {
        return address(this).balance;
    }

    // TODO: verify this
    function sqrt(uint x) internal pure returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
    
}
