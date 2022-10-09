//
//  UserDefaultsExtension.swift
//  Demo
//
//  Created by 李响 on 2022/9/29.
//

import Foundation

extension UserDefaults {
    
     func model<T: Decodable>(forKey key: String) -> T? {
        if let data = UserDefaults.standard.data(forKey: key) {
            return try? JSONDecoder().decode(T.self, from: data)
        }
        return nil
    }
    
    func set<T: Encodable>(model: T?, forKey key: String) {
        if let model = model {
            let encoded = try? JSONEncoder().encode(model)
            UserDefaults.standard.set(encoded, forKey: key)
            
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
