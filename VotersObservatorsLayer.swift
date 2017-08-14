//
//  VotersObservators.swift
//  Parrou
//
//  Created by Kamil Wójcik on 06.07.2017.
//  Copyright © 2017 Kamil Wójcik. All rights reserved.
//

import Foundation
import Firebase

class VotersObservatorsLayer: VotersDataLayer{
    
    func newVoterAdded(fromRef ref: DatabaseQuery, completion: @escaping (Voter) -> Void){
        
        ref.observe(.childAdded, with: { (snapshotAdded) in
            
            DataService.ds.REF_USERS.child(snapshotAdded.key).observeSingleEvent(of: .value, with: { (snapshot) in
                
                guard let voterDict = snapshot.value as? [String: Any] else { return }
                
                let voter = Voter(userDict: voterDict, uid: snapshotAdded.key, alreadyFollowed: false)
                
                completion(voter)
                
                })
        })
    }
    
    func voterRemoved(fromRef ref: DatabaseQuery, completion: @escaping (String) -> Void){
        
        ref.observe(.childRemoved, with: { (voterRemoved) in
            
            let voterUID = voterRemoved.key
                
            completion(voterUID)

        })
    }
    
}
