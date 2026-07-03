//
//  FriendCampWidgetLiveActivity.swift
//  FriendCampWidget
//
//  Created by Vaceff Vlad on 03/07/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct FriendCampWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct FriendCampWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FriendCampWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension FriendCampWidgetAttributes {
    fileprivate static var preview: FriendCampWidgetAttributes {
        FriendCampWidgetAttributes(name: "World")
    }
}

extension FriendCampWidgetAttributes.ContentState {
    fileprivate static var smiley: FriendCampWidgetAttributes.ContentState {
        FriendCampWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: FriendCampWidgetAttributes.ContentState {
         FriendCampWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: FriendCampWidgetAttributes.preview) {
   FriendCampWidgetLiveActivity()
} contentStates: {
    FriendCampWidgetAttributes.ContentState.smiley
    FriendCampWidgetAttributes.ContentState.starEyes
}
