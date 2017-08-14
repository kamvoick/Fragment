//
//  FetchingFollowedFollowers.swift
//  Parrou
//
//  Created by Kamil Wójcik on 05.07.2017.
//  Copyright © 2017 Kamil Wójcik. All rights reserved.
//

import Foundation
import Firebase

class VotersDataLayer {
     
    func fetchVoters(fromRef ref: DatabaseQuery, completion: @escaping ([Voter]) -> Void){
        
        var tempDict: [Voter] = [Voter]()
        
        ref.observeSingleEvent(of: .value, with: {  (usernameSnapshot) in
            
            guard usernameSnapshot.exists() else { return completion(tempDict) }
            
            guard let searchedVoters = usernameSnapshot.children.allObjects as? [DataSnapshot] else { return }
            
            let fetchGroup = DispatchGroup()
            
            DispatchQueue.concurrentPerform(iterations: searchedVoters.count, execute: { (voter) in
                
                fetchGroup.enter()
                
                guard let subscribedTimestamp = searchedVoters[voter].childSnapshot(forPath: "subscribedTimestamp").value as? Int64 else { return completion(tempDict) }

                self.loadVoterAndCheckIfAlreadyFollowed(voterUID: searchedVoters[voter].key, completion: { (voter) in
                    
                    guard let voter = voter else { return fetchGroup.leave() }
                    
                    voter.subscribedTimestamp = subscribedTimestamp
                    
                    let orderedIndex = tempDict.insertionIndexOf(elem: voter, isOrderedBefore: { $0.subscribedTimestamp! > $1.subscribedTimestamp! })
                    
                    tempDict.insert(voter, at: orderedIndex)
                    
                    fetchGroup.leave()
                })
            })
            
            fetchGroup.notify(queue: DispatchQueue.global(qos: .userInitiated) , execute: {
                
                completion(tempDict)

            })

        })
    }
    
    func loadVoterAndCheckIfAlreadyFollowed(voterUID: String, completion: @escaping (Voter?) -> Void){
        
        var loadingComplete: (userDict: (success: Bool, dict: [String:Any])?, alreadyFollowed: Bool?) {
            didSet{
                guard let userDict = loadingComplete.userDict, let alreadyFollowed = loadingComplete.alreadyFollowed else { return }
                
                guard userDict.success else { return completion(nil) }
                
                let voter = Voter(userDict: userDict.dict, uid: voterUID, alreadyFollowed: alreadyFollowed)
                
                completion(voter)
            }
        }
        
        if let userUID = User.logged?.uid
        {
            DataService.ds.REF_USERS.child(userUID).child("followed").child(voterUID).observeSingleEvent(of: .value, with: { (followingUser) in
                
                loadingComplete.alreadyFollowed = followingUser.exists()
                
            }, withCancel: { (_) in
                
                loadingComplete.alreadyFollowed = false
            })
        }
        else
        {
            loadingComplete.alreadyFollowed = false
        }
        
        DataService.ds.REF_USERS.child(voterUID).observeSingleEvent(of: .value, with: { (snapshot) in
            
            guard let voterDict = snapshot.value as? [String: Any] else { return }
            
            loadingComplete.userDict = (success: true, dict: voterDict)
            
        }, withCancel: { (_) in
            
            loadingComplete.userDict = (success: false, dict: [String:Any]())
        })
    }
    
    deinit {
        print("fetching deinit func")
    }
}
