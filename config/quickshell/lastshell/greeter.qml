import Quickshell
import "greeter"

// Entry point for the login screen:  qs -p greeter.qml
// Lives at the repo root so the greeter shares lastshell's module.
ShellRoot { Greeter {} }
