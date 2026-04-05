import Foundation


let state = State.shared //singleton...

let listener = XPCListener()

if (state.currentData.running == true) { //handle power loss/unexpected shutdown
    listener.endConnection() { _ in }
}

listener.start()

