Set sh = CreateObject("WScript.Shell")
sh.Run """C:\Program Files\Git\bin\bash.exe"" -c ""/c/Users/misha/.claude/hooks/workstreams-emit.sh --heartbeat""", 0, False
