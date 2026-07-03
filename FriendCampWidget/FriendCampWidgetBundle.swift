//
//  FriendCampWidgetBundle.swift
//  FriendCampWidget
//
//  Created by Vaceff Vlad on 03/07/2026.
//

import WidgetKit
import SwiftUI

@main
struct FriendCampWidgetBundle: WidgetBundle {
    var body: some Widget {
        FriendCampWidget()
        FriendCampWidgetControl()
        FriendCampWidgetLiveActivity()
    }
}
