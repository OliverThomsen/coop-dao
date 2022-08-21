// SPDX-License-Identifier: MIT

// referrel program - get points

// adgang til kode skiller sig ud fra andre
// central sted hvor kun crypto wallets har adgang til koden
// wallet 


// non member kan betale for brug af software uden adgagn til source kode


/// stem pa eget forslag giver points ?

pragma solidity ^0.8.0;

/**
 * @author Oliver Elleman Thomsen
 * 
 */
contract DAO {

    // CONSTANTS
    uint private constant MONTH_IN_SECONDS = 2629800; // (365.25 / 12 * 24 * 60 * 60)

    // CONFIGURATION ATTRIBUTES
    uint8 public quorum; // minimum percentage of people requiret to participate in vote
    uint public minBuyIn; // the minimum price to join the DAO
    uint public voteTime; // period of time in seconds where it is possiple to vote on a proposal
    uint public votingReward; // the amount of points a member is rewarded for participating in a vote
    uint public monthlyContribution; // the price you must pay every month to stay a member
    
    address public creator;
    uint public latestProposalId = 0;
    uint public numberOfMembers = 0;

    mapping(address => Member) public members;
    mapping(address => uint) public fundsToWithdraw;
   
    mapping(uint => Proposal) public proposals;
    mapping(uint => SpendingProposal) public spendingProposals;
    mapping(uint => ConfigurationProposal) public configurationProposals;
    mapping(address => mapping(uint => bool)) public memberVotedOnProposal; // memberAddress => proposalId => hasVoted

    mapping(address => JoinRequest) public joinRequests;
    mapping(address => mapping(address => bool)) public memberApprovedRequest; // requestApprovedByMember; // memberAddress => requesterAddress => hasApproved

    // EVENTS
    event NewJoinRequest(address from);
    event NewMember(address member);
    event NewProposal(Proposal proposal);
    event ProposalRealized(uint proposalId);

    struct Member {
        uint points;
        uint lastPaymentTime;
        bool exists;
    }

    struct Proposal {
        uint id;
        address proposer;
        uint endTime;
        uint yesVotes;
        uint noVotes;
        uint numMembersVoted;
        bool realized;
        SpendingProposal spendingProposal;
        ConfigurationProposal configurationProposal;
    }

    struct SpendingProposal {
        string name;
        uint amount;
        address payable recipient;
        bool exists;
    }

    struct ConfigurationProposal {
        uint8 quorum;
        uint minBuyIn;
        uint voteTime;
        uint votingReward;
        uint monthlyContribution;
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


    constructor(uint _minBuyIn, uint _monthlyContribution,  uint _votingReward, uint8 _quorum, uint _voteTime) payable {
        require(_quorum > 0 && _quorum <= 100, "Quorum must be between 0 and 100");
        creator = msg.sender;
        minBuyIn = _minBuyIn;
        monthlyContribution = _monthlyContribution;
        quorum = _quorum;
        voteTime = _voteTime;
        votingReward = _votingReward;
        members[msg.sender] = Member({
            points: msg.value,
            lastPaymentTime: getNextPaymentTime(),
            exists: true
        });
        numberOfMembers += 1;
    }

    function fund() external payable onlyMembers {
        members[msg.sender].points += msg.value;
    }

    // Send a request to join the DAO 
    // Other members must accept the request  
    function requestToJoin(uint _buyIn) external onlyNonMembers {
        require(joinRequests[msg.sender].send == false, "You already send a join request");
        require(_buyIn >= minBuyIn, "Buy in value too low");
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
    // Maybe add a voting protocol to the approve new members
    function approveJoinRequest(address requester) external onlyActiveMembers {
        require(joinRequests[requester].send == true, "This address has not send a join request");
        require(memberApprovedRequest[msg.sender][requester] == false, "You have already approved this join request");
        memberApprovedRequest[msg.sender][requester] = true;
        joinRequests[requester].approvals += 1;
    }

    // msg.value is in the unit Wei. 1 Ether = 10^18 Wei
    function join() payable external onlyNonMembers {
        require(joinRequests[msg.sender].send == true, "You need to send a join request before you can join");
        require(joinRequests[msg.sender].approvals * 100 >= quorum * numberOfMembers, "Your request to join has not been approved by enough members");
        require(msg.value == joinRequests[msg.sender].buyIn, "Value must be the same as buyIn in the joinRequest");
        delete joinRequests[msg.sender]; // delete sets all values in the srtuct to their default value
        members[msg.sender] = Member({
            points: msg.value,
            lastPaymentTime: getNextPaymentTime(),
            exists: true
        });
        numberOfMembers += 1; // lookup what actually happens 
        emit NewMember(msg.sender);
    }

    // Leave the DAO, stop spending monthly membership fee
    // Loose access to source code
    // TODO
    function leave() external onlyMembers {
        delete members[msg.sender];
        numberOfMembers -= 1;
    }

    // Propose to spend money
    function createSpedingProposal(uint amount, address payable recipient, string memory name) external onlyActiveMembers {
        require(address(this).balance >= amount, "Not enough funds");
        SpendingProposal memory spendingProposal = SpendingProposal({
            name: name,
            amount: amount,
            recipient: recipient,
            exists: true

        });
        ConfigurationProposal memory emptyConfigProposal;
        createProposal(spendingProposal, emptyConfigProposal);
    }

    // propose vote to change global params
    function createConfigurationProposal(uint8 _quorum, uint _minBuyIn, uint _voteTime,  uint _votingReward, uint _monthlyContribution) external onlyActiveMembers {
        ConfigurationProposal memory configurationProposal = ConfigurationProposal({
            quorum: _quorum,
            minBuyIn: _minBuyIn,
            voteTime: _voteTime,
            votingReward: _votingReward,
            monthlyContribution: _monthlyContribution,
            exists: true
        });
        SpendingProposal memory emptySpendingProposal;
        createProposal(emptySpendingProposal, configurationProposal);
    }

    function createProposal(SpendingProposal memory sp, ConfigurationProposal memory cp) internal onlyActiveMembers {
        latestProposalId += 1;
        proposals[latestProposalId] = Proposal({
            id: latestProposalId,
            proposer: msg.sender,
            endTime: block.timestamp + voteTime,
            yesVotes: 0,
            noVotes: 0,
            numMembersVoted: 0,
            realized: false,
            spendingProposal: sp,
            configurationProposal: cp
        });
        emit NewProposal(proposals[latestProposalId]);
    }

    // Vote on a proposal and get rewarded with points
    // maybe proof 
    function vote(uint proposalId, bool votingYes) external onlyActiveMembers {
        require(proposalId <= latestProposalId && proposalId > 0, "No proposal exists with this id");
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

    // TODO 
    function payMonthlyContribution() external payable onlyMembers {
        uint monthsToPay = (getNextPaymentTime() - members[msg.sender].lastPaymentTime) / MONTH_IN_SECONDS;
        require(monthsToPay == 0, "You have already payed for this month");
        require(msg.value == monthlyContribution * monthsToPay, "Value does not equal required monthly contrubution");
        members[msg.sender].points += msg.value;  // get points equivalent to amount of ETH
        members[msg.sender].lastPaymentTime = getNextPaymentTime();
    }

    function realizeProposal(uint id) external onlyActiveMembers {
        require(id <= latestProposalId && id > 0, "No proposal exists with this id");
        require(proposals[id].endTime <= block.timestamp, "Voting peroid is not over");
        require(proposals[id].realized == false, "Proposal already realized");
        // multiply with 100 before dividing to avoid rounding error
        require((proposals[id].numMembersVoted  * 100) / numberOfMembers >= quorum, "Not enough members participated in the vote");
        require(proposals[id].yesVotes >= proposals[id].noVotes, "Proposal did not pass vote");
        require(proposals[id].spendingProposal.amount <= address(this).balance, "Not enough funds to complete proposal");
    
        if (proposals[id].spendingProposal.exists) {
            fundsToWithdraw[proposals[id].spendingProposal.recipient] += proposals[id].spendingProposal.amount;
        }
        if (proposals[id].configurationProposal.exists) {
            updateConfigurations(id);
        }
        proposals[id].realized = true;
        
        emit ProposalRealized(id);
    }

    function updateConfigurations(uint proposalId) internal onlyActiveMembers {
        ConfigurationProposal storage proposal = proposals[proposalId].configurationProposal;
        quorum = proposal.quorum;
        minBuyIn = proposal.minBuyIn;
        voteTime = proposal.voteTime;
        votingReward = proposal.votingReward;
        monthlyContribution = proposal.monthlyContribution;
    }

    // Returns time left on proposal in seconds
    function getTimeLeftOnProposal(uint id) public view returns(uint) {
        require(id <= latestProposalId && id > 0, "No proposal exists with this id");
        uint endTime = proposals[id].endTime;
        return endTime - block.timestamp;
    } 

    function widthdrawFunds() external {
        uint amount = fundsToWithdraw[msg.sender];
        require(amount > 0, "You have no funds to withdraw");
        // resetting funds before transfering to prevent reentrancy attack
        fundsToWithdraw[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }

    function isActive(address memberAddress) internal view returns(bool) {
        return members[memberAddress].lastPaymentTime == getNextPaymentTime();
    }

    function getNextPaymentTime() public view returns(uint) {
        uint timeSinceLastPayment = block.timestamp % MONTH_IN_SECONDS;
        if (timeSinceLastPayment == 0) {
            return block.timestamp;
        } else {
            return block.timestamp + MONTH_IN_SECONDS - timeSinceLastPayment;
        }
    }

    function getBalance() external view returns(uint) {
        return address(this).balance;
    }

    // verify this
    function sqrt(uint x) internal pure returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
    
}
