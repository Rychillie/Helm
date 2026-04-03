//
//  Item.swift
//  Helm
//
//  Created by Rychillie Umpierre de Oliveira on 02/04/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
