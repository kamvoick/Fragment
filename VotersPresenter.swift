//
//  VotersPresenter.swift
//  Parrou
//
//  Created by Kamil Wójcik on 04.07.2017.
//  Copyright © 2017 Kamil Wójcik. All rights reserved.
//

import Foundation
import Firebase

class VotersPresenter {
    
    fileprivate var votersDataLayer = VotersDataLayer()
    fileprivate var votersObservatorsLayer = VotersObservatorsLayer()
    fileprivate var votersSearchLayer = VotersSearchLayer()
    
    var followed : VotersData?{
        willSet{
            loadingFollowedState.itemCount = newValue?.list.count ?? 0
        }
    }
    var followers : VotersData?{
        willSet{
            loadingFollowersState.itemCount = newValue?.list.count ?? 0
        }
    }
    
    enum Voters {
        case followed, followers
        func ref(uid: String) -> DatabaseQuery{
            switch self {
            case .followed:
                return DataService.ds.REF_USERS.child(uid).child("followed")
            case .followers:
                return DataService.ds.REF_BASE.child("followers").child(uid)
            }
        }
    }
    
    func loading(_ userVoters: Voters, ofUserUID uid: String, perOneTime: UInt, completion: ((Int) -> Void)?){
        
        let ref = userVoters.ref(uid: uid).queryOrdered(byChild: "subscribedTimestamp").queryLimited(toLast: perOneTime)
        
        votersDataLayer.fetchVoters(fromRef: ref) { (votersDict) in
            
            switch userVoters{
            case .followed:
                self.followed = VotersData(data: votersDict, ref: ref)
            case .followers:
                self.followers = VotersData(data: votersDict, ref: ref)
            }
            completion?(votersDict.count)
        }
    }
    
    struct State {
        var itemCount: Int = 0 {
            didSet{
                print("itemCount changed to \(itemCount)")
                initialLoading = false
            }
        }
        var initialLoading: Bool = true
        var fetchingMore: Bool = false
        var noMoreVoters: Bool = false
        var zeroVoters: Bool = false
        static let initial = State()
    }
    
    var loadingFollowedState: State = .initial
    var loadingFollowersState: State = .initial
    
}

//MARK: - Paths Observators
extension VotersLoadPresenter {
    
    enum Changes {
        case voterRemoved(key: String)
        case voterAdded
    }

    typealias ChangesObservedOnPath = (Changes, IndexPath) -> Void
    func observeChanges(on userVoters: Voters, ofUserUID uid: String, completion: @escaping ChangesObservedOnPath){
        
        guard let voters = (userVoters == .followed) ? self.followed : self.followers else { return }
        
        votersObservatorsLayer.newVoterAdded(fromRef: voters.newestVoterRef) { [weak voters] (voter) in
            
            voters?.list.insert(voter, at: 0)
            
            completion(.voterAdded, IndexPath(item: 0, section: 0))
        }

        votersObservatorsLayer.voterRemoved(fromRef: voters.oldestVoterRef) { [weak voters] (uid) in
            
            guard let index = voters?.list.index(where: { $0.uid == uid }) else { return }
            
            voters?.list.remove(at: index)
            
            completion(.voterRemoved(key: uid), IndexPath(item: index, section: 0))
        }
    }
}

//MARK: - Search voters methods
extension VotersLoadPresenter {
    
    struct SearchState{
        var itemCount: Int = 0{
            didSet{
                print("itemCount changed to \(itemCount)")
            }
        }
        var notEnoughLetters: Bool = true
        var noResults: Bool = false
        var initialLoading: Bool = true
        static let empty = SearchState()
        
    }
    
    func searchThrough(_ userVoters: Voters, ofUserUID uid: String, voterName name: String, completion: (() -> Void)?){
        
        let ref = userVoters.ref(uid: uid).queryOrdered(byChild: "username").queryStarting(atValue: name).queryEnding(atValue: name + "\u{f8ff}")
        
        votersDataLayer.searchVoter(name: name, fromRef: ref) { [weak self] (votersDict) in
            
            switch userVoters{
            case .followed:
                self?.followed = VotersData(data: votersDict, ref: ref)
            case .followers:
                self?.followers = VotersData(data: votersDict, ref: ref)
            }
            completion?()
        }
    }
    
    private weak var pendingRequestWorkItem : DispatchWorkItem?
    private weak var pendingCompletionRequestWorkItem : DispatchWorkItem?
    
    func searchingWithDebounce(_ userVoters: Voters, ofUserUID uid: String, voterName name: String, completion: (() -> Void)?){
        
        pendingRequestWorkItem?.cancel()
        
        let requestWorkItem = DispatchWorkItem(block: {
            
            self.pendingCompletionRequestWorkItem?.cancel()
            
            let completionRequestWorkItem = DispatchWorkItem(block: {
                
                completion()
                
            })
            
            self.pendingCompletionRequestWorkItem = completionRequestWorkItem
            
            self.searchThrough(userVoters, ofUserUID: uid, voterName: name, completion: {
                
                completionRequestWorkItem.perform()
            })
            
        })
        
        pendingRequestWorkItem = requestWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500), execute: requestWorkItem)
    }
    
}

//MARK: - Batch fetching methods
extension VotersLoadPresenter {
    
    fileprivate enum Action {
        case beginBatchFetch
        case endBatchFetch(resultCount: Int)
    }
    
    fileprivate static func handleAction(_ action: Action, fromState state: State) -> State {
        var state = state
        switch action {
        case .beginBatchFetch:
            state.fetchingMore = true
        case let .endBatchFetch(resultCount):
            state.itemCount += resultCount
            state.fetchingMore = false
        }
        return state
        
    }
    
    func configureNextBatch(of userVoters: Voters, fetchingStarted: ((State, State) -> Void)?, fetchingCompleted: @escaping (State, State) -> Void){
        
        let oldState = userVoters == .followed ? self.loadingFollowedState : self.loadingFollowersState
        
        let newState = VotersLoadPresenter.handleAction(.beginBatchFetch, fromState: oldState)
        fetchingStarted!(newState, oldState)
        
        if userVoters == .followed { self.loadingFollowedState = newState } else { self.loadingFollowersState = newState }
        
        loadNextBatch(of: userVoters) { (loadedVoters) in
            
            let action = Action.endBatchFetch(resultCount: loadedVoters)
            var newestState = VotersLoadPresenter.handleAction(action, fromState: newState)
            fetchingCompleted(newestState, oldState)
            
            newestState.noMoreVoters = loadedVoters == 0 ? true : false
            
            if userVoters == .followed { self.loadingFollowedState = newestState } else { self.loadingFollowersState = newestState }
        }
        
    }
    
    fileprivate func loadNextBatch(of userVoters: Voters, completion: @escaping (Int) -> Void){
        
        switch userVoters{
        case .followed:
            guard followed != nil else { return }
            
            votersDataLayer.fetchVoters(fromRef: followed!.ref) { [weak self] (votersDict) in
                self?.followed!.list.append(contentsOf: votersDict)
                completion(votersDict.count)
            }
        case .followers:
            guard followers != nil else { return }
            
            votersDataLayer.fetchVoters(fromRef: followers!.ref) { [weak self] (votersDict) in
                self?.followers!.list.append(contentsOf: votersDict)
                completion(votersDict.count)
            }
        }
    }
    
    
}

class VotersData{
    var list: [Voter] = [Voter]()
    
    var ref: DatabaseQuery{
        didSet{
            guard let subscribedTimestamp = list.last?.subscribedTimestamp else { return }
            let oldestTimestamp = subscribedTimestamp - 1
            oldestVoterRef = ref.queryEnding(atValue: oldestTimestamp)
        }
    }
    var newestVoterRef: DatabaseQuery
    var oldestVoterRef: DatabaseQuery
    
    init(data: [Voter], ref: DatabaseQuery) {
        self.list = data
        self.ref = ref
        
        guard let subscribedTimestamp = list.first?.subscribedTimestamp else { return }
        let newestTimestamp = subscribedTimestamp + 1
        newestVoterRef = ref.queryStarting(atValue: newestTimestamp)
    }
    
}
