//
//  VotersSearchLayer.swift
//  Parrou
//
//  Created by Kamil Wójcik on 06.07.2017.
//  Copyright © 2017 Kamil Wójcik. All rights reserved.
//

import Foundation
import Firebase

class VotersSearchLayer : VotersDataLayer{
    
    func searchVoter(name: String, fromRef ref: DatabaseQuery, completion: @escaping ([Voter]) -> Void){
        
        var tempDict: [Voter] = [Voter]()
        
        let name = name.firstLetterLowercase()
        
        ref.observeSingleEvent(of: .value, with: { (usernameSnapshot) in
            
            guard usernameSnapshot.exists() else { return completion(tempDict) }
            
            guard let searchedVoters = usernameSnapshot.children.allObjects as? [DataSnapshot] else { return }
            
            let fetch = DispatchGroup()
            
            DispatchQueue.concurrentPerform(iterations: searchedVoters.count, execute: { (voter) in
                
                fetch.enter()
                
                self.loadVoterAndCheckIfAlreadyFollowed(voterUID: searchedVoters[voter].key, completion: { (voter) in
                    
                    guard let voter = voter else { return fetchGroup.leave() }
                    
                    voter.subscribedTimestamp = subscribedTimestamp
                    
                    let orderedIndex = tempDict.insertionIndexOf(elem: voter, isOrderedBefore: { $0.subscribedTimestamp! > $1.subscribedTimestamp! })
                    
                    tempDict.insert(voter, at: orderedIndex)
                    
                    fetch.leave()
                })
            })
            
            fetch.notify(queue: DispatchQueue.main, execute: {
                completion(tempDict)
            })
        })
    }
    
    

}
