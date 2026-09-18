import os

/// `log stream --predicate 'subsystem == "com.mokotahi.mailpit-menubar"' --level info` to follow.
let log = Logger(subsystem: "com.mokotahi.mailpit-menubar", category: "app")
