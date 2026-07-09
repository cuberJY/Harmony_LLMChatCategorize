$path = "d:\ZJY\Code\ChatCategorize\entry\src\main\ets\pages\Index.ets"
$content = [System.IO.File]::ReadAllText($path)
# Fix empty strings that got triple-quoted
$content = $content.Replace("='''''", "=''")
$content = $content.Replace("=== '''''", "=== ''")
$content = $content.Replace("= '''''", "= ''")
$content = $content.Replace("''new", "'new")
$content = $content.Replace("new Conversation(0, '''''')", "new Conversation(0, '')")
[System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
