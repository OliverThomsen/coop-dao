// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract DAO {
    struct Proposal {
        uint id;
        string name;
        uint amount;
        address payable recipient;
        uint endTime;
        uint yesVotes;
        uint noVotes;
        uint numMembersVoted;
        bool completed;
        bool exists;
    }

    struct JoinRequest {
        address requester;
        bool send; 
        bool approved;
        uint buyIn;
    }

    uint8 private quorum; // minimum percentage of people requiret to participate in vote
    uint public minBuyIn; // the minimum price to join the DAO
    uint private voteTime; // period of time where it is possiple to vote on a proposal
    uint private votingReward; // the amount of points a member is rewarded for participating in a vote
    uint private monthlyContribution; // the price you must pay every month to stay a member
    address public creator;
    
    uint public latestProposalId = 0;
    uint private numberOfMembers = 0;

    mapping(address => bool) public members;
    mapping(address => uint) public memberPoints;
    mapping(address => uint) public fundsToWithdraw;
    mapping(uint => Proposal) public proposals;
    mapping(address => JoinRequest) private joinRequests;
    mapping(address => mapping(uint => bool)) private memberVotedOnProposal;

    // todo add events ...


    modifier onlyMembers {
        require(members[msg.sender] == true, 'Only members can call this function');
        _; // function body is executed here
    }

    modifier onlyNonMembers {
        require(members[msg.sender] == false, 'Only non members can call this function');
        _;
    }


    constructor(uint _minBuyIn, uint _monthlyContribution, uint8 _quorum, uint _voteTime, uint _votingReward) payable {
        require(_quorum > 0 && _quorum < 100, 'Quorum must be between 0 and 100');
        creator = msg.sender;
        minBuyIn = _minBuyIn;
        monthlyContribution = _monthlyContribution;
        quorum = _quorum;
        voteTime = _voteTime;
        votingReward = _votingReward;
        members[msg.sender] = true;
        memberPoints[msg.sender] = msg.value;
        numberOfMembers += 1;
    }

    function fund() external payable onlyMembers {
        memberPoints[msg.sender] += msg.value;
    }

    // Send a request to join the DAO 
    // Other members must accept the request  
    function requestToJoin(uint buyIn) external onlyNonMembers {
        require(joinRequests[msg.sender].send == false, 'You already send a join request');
        require(buyIn >= minBuyIn, 'Buy in value too low');
        joinRequests[msg.sender] = JoinRequest(msg.sender, true, false, buyIn);
    }


    // Maybe add voting on new members...
    function approveJoinRequest(address newMember) external onlyMembers {
        require(joinRequests[newMember].send == true, 'This address has not send a join request');
        require(members[newMember] == false, 'Address is already a member');
        joinRequests[newMember].approved = true;
    }

    // msg.value is in the unit Wei. 1 Ether = 10^18 Wei
    function join() payable external onlyNonMembers {
        JoinRequest memory joinRequest = joinRequests[msg.sender];
        require(joinRequest.send == true, 'You need to send a join request before you can join');
        require(joinRequest.approved == true, 'Your request to join has not been approved');
        require(msg.value == joinRequest.buyIn, 'Value must be the same as buyIn in the joinRequest');
        delete joinRequests[msg.sender];
        members[msg.sender] = true;
        memberPoints[msg.sender] += msg.value; // get points equivalent to amount of ETH 
        numberOfMembers += 1; // lookup what actually happens 
    }

    function leave() external onlyMembers {
        delete members[msg.sender];
        numberOfMembers -= 1;
    }

    // Propose to spend money
    function proposeVote(uint amount, address payable recipient, string memory name) external onlyMembers {
        require(address(this).balance >= amount, 'Not enough funds');
        latestProposalId += 1;
        proposals[latestProposalId] = Proposal(latestProposalId, name, amount, recipient, block.timestamp + voteTime, 0, 0, 0, false, true);
    }


    // Vote on a proposal and get rewarded with points
    // maybe proof 
    function vote(uint proposalId, bool votingYes) external onlyMembers {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.exists == true, 'No proposal exists with this id');
        require(proposal.endTime > block.timestamp, 'Voting period has ended');
        require(memberVotedOnProposal[msg.sender][proposalId] == false, 'You have already voted once');
        memberVotedOnProposal[msg.sender][proposalId] = true;
        // Quadratic voting: take square root of points to make it harder to buy power
        uint weightedVote = sqrt(memberPoints[msg.sender]);
        if (votingYes) {
            proposal.yesVotes = weightedVote;
        } else {
            proposal.noVotes = weightedVote;
        }
        proposal.numMembersVoted += 1;
        memberPoints[msg.sender] += votingReward;
    }

    function payMonthlyContribution() external payable onlyMembers {
        memberPoints[msg.sender] += msg.value;  // get points equivalent to amount of ETH
    }


    function completeProposal(uint id) external onlyMembers {
        Proposal storage proposal = proposals[id];
        require(proposal.endTime <= block.timestamp, 'Voting peroid is not over');
        require(proposal.completed == false, 'Proposal already completed');
        require(proposal.numMembersVoted / numberOfMembers * 100 >= quorum, 'Not enough members participated in the vote');
        require(proposal.yesVotes >= proposal.noVotes, 'Proposal did not pass vote');
        require(proposal.amount <= address(this).balance, 'Not enough funds to complete proposal');
        proposals[id].completed = true;
        fundsToWithdraw[proposal.recipient] += proposal.amount;
    }

    function widthdrawFunds() external {
        uint amount = fundsToWithdraw[msg.sender];
        // resetting funds before transfering to prevent reentrancy attack
        fundsToWithdraw[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
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
