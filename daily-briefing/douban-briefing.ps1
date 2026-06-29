#requires -Version 5.1

param([switch]$Test)

$Config = @{
    GroupUrl     = "https://www.douban.com/group/698716/"
    SmtpServer   = "smtp.qq.com"
    SmtpPort     = 587
    FromEmail    = "haoyanghan@foxmail.com"
    FromPassword = if ($env:SMTP_PASSWORD) { $env:SMTP_PASSWORD } else { "nvyhgmybgryfcbbf" }
    ToEmail      = "haoyanghan@foxmail.com"
}

$ExcludeKeywords   = @("刷券", "付邮送", "闲置", "求购")
$PriorityKeywords  = @("神价", "速度", "0元", "免费", "反薅")
$IncludeCategories = @("作业", "教程", "交流")

$DateStr = Get-Date -Format "yyyy-MM-dd"

function Get-PostAge {
    param([string]$TimeStr)
    if ($TimeStr -match "(\d{2})-(\d{2}) (\d{2}):(\d{2})") {
        $month = [int]$matches[1]; $day = [int]$matches[2]
        $hour  = [int]$matches[3]; $min  = [int]$matches[4]
        $now   = Get-Date
        $postTime = Get-Date -Year $now.Year -Month $month -Day $day -Hour $hour -Minute $min -Second 0
        if ($postTime -gt $now) { $postTime = $postTime.AddYears(-1) }
        return [math]::Round(($now - $postTime).TotalHours, 1)
    }
    return 999
}

function Extract-Posts {
    param([string]$Html)
    $posts = @()
    $rows = $Html -split "<tr class="
    foreach ($row in $rows) {
        if ($row -notmatch "topic/\d+") { continue }
        if ($row -match "置顶|elite_topic_lable") { continue }

        $url = ""
        $m = [regex]::Match($row, 'href="(https?://[^"]+topic/(\d+)/[^"]*)"')
        if ($m.Success) { $url = $m.Groups[1].Value -replace '&amp;', '&' }

        $titleText = ""
        $m2 = [regex]::Match($row, '<a[^>]*title="([^"]*)"')
        if ($m2.Success) { $titleText = $m2.Groups[1].Value -replace '&amp;', '&' }

        $displayText = ""
        $mDisplay = [regex]::Match($row, 'class="">\s*([^<]+?)\s*</a>')
        if ($mDisplay.Success) { $displayText = $mDisplay.Groups[1].Value -replace '&amp;', '&' }

        $category = ""
        $pipeIdx = $displayText.IndexOf([char]0xFF5C)
        if ($pipeIdx -ge 0) { $category = $displayText.Substring(0, $pipeIdx).Trim() }

        $author = ""
        $m3 = [regex]::Match($row, 'people/\d+/"[^>]*>([^<]+?)<')
        if ($m3.Success) { $author = $m3.Groups[1].Value }

        $replies = 0
        $m4 = [regex]::Match($row, 'r-count[^>]*>(\d+)<')
        if ($m4.Success) { $replies = [int]$m4.Groups[1].Value }

        $time = ""
        $m5 = [regex]::Match($row, 'class="time">([^<]+)<')
        if ($m5.Success) { $time = $m5.Groups[1].Value }

        if ($url -and $titleText) {
            $posts += [PSCustomObject]@{
                Url=$url; Title=$titleText; Category=$category
                Author=$author; Replies=$replies; Time=$time
                AgeHours=Get-PostAge $time; DisplayText=$displayText
            }
        }
    }
    return $posts
}

Write-Host "`n=== Briefing $DateStr ==="

Write-Host "[1] Fetching..."
try {
    $r = Invoke-WebRequest -Uri $Config.GroupUrl -UseBasicParsing -TimeoutSec 15 `
        -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    $html = $r.Content
    Write-Host ("OK (" + $html.Length + " bytes)")
} catch {
    Write-Host ("FAIL: " + $_.Exception.Message); exit 1
}

Write-Host "[2] Parsing..."
$allPosts = Extract-Posts $html
Write-Host ("Found " + $allPosts.Count + " posts")

Write-Host "[3] Filtering..."
$filtered = $allPosts | Where-Object { $skip=$false; foreach($kw in $ExcludeKeywords){if($_.Title -match $kw -or $_.DisplayText -match $kw -or $_.Category -match $kw){$skip=$true;break}}; -not $skip }
$interest = $filtered | Where-Object { $_.Category -in $IncludeCategories -or $_.Category -eq "" }
$priority = $interest | Where-Object { $matched=$false; foreach($kw in $PriorityKeywords){if($_.Title -match $kw){$matched=$true;break}}; $matched } | Sort-Object Replies -Descending
$normal   = $interest | Where-Object { $matched=$false; foreach($kw in $PriorityKeywords){if($_.Title -match $kw){$matched=$true;break}}; -not $matched } | Sort-Object AgeHours
$hot      = $interest | Where-Object { $_.Replies -ge 100 } | Sort-Object Replies -Descending
Write-Host ("Priority: " + $priority.Count + ", Normal: " + $normal.Count + ", Hot: " + $hot.Count)

Write-Host "[4] Generating..."

$body = @"
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><style>
body{font-family:-apple-system,'Microsoft YaHei',sans-serif;max-width:680px;margin:0 auto;padding:20px;background:#f5f5f5;color:#333}
.hdr{background:linear-gradient(135deg,#ff6b6b,#ee5a24);color:#fff;padding:20px 25px;border-radius:12px;margin-bottom:16px}
.hdr h1{margin:0;font-size:20px}.hdr p{margin:6px 0 0;opacity:.9;font-size:13px}
.sec{background:#fff;border-radius:10px;padding:14px 18px;margin-bottom:12px;box-shadow:0 1px 3px rgba(0,0,0,.08)}
.sec h2{margin:0 0 10px;font-size:15px;color:#ee5a24;border-bottom:2px solid #fee;padding-bottom:6px}
.pst{padding:6px 0;border-bottom:1px solid #f0f0f0;font-size:13px}
.pst:last-child{border-bottom:none}
.pst .tag{display:inline-block;background:#fee;color:#ee5a24;font-size:10px;padding:1px 5px;border-radius:3px;margin-right:3px}
.pst .tag-p{background:#ff6b6b;color:#fff}
.pst a{color:#333;text-decoration:none}
.pst a:hover{color:#ee5a24}
.pst .meta{font-size:11px;color:#999;margin-top:2px}
.pri{background:#fff3cd;border-left:3px solid #ffc107;padding:10px 14px;border-radius:4px;margin:12px 0;font-size:12px;color:#856404}
.footer{text-align:center;color:#aaa;font-size:11px;padding:16px}
</style></head>
<body>
<div class="hdr">
  <h1>今日薅羊毛简报</h1>
  <p>$DateStr | 买组 &amp; All buy</p>
</div>
"@

if ($priority.Count -gt 0) {
    $body += '<div class="sec"><h2>⭐ 优先推荐</h2>'
    foreach ($p in $priority) {
        $t = "<span class='tag tag-p'>" + $p.Category + "</span>"
        $body += "<div class='pst'><div class='title'>$t <a href='" + $p.Url + "'>" + $p.Title + "</a></div>"
        $body += "<div class='meta'>" + $p.Author + " | " + $p.Replies + " 回复 | " + $p.Time + "</div></div>"
    }
    $body += '</div>'
}

if ($normal.Count -gt 0) {
    $body += '<div class="sec"><h2>📦 作业精选</h2>'
    $n=0
    foreach ($p in $normal) {
        if ($n -ge 25) { break }
        $t = ""
        if ($p.Category) { $t = "<span class='tag'>" + $p.Category + "</span>" }
        $b = ""
        if ($p.Replies -ge 50) { $b = " 🔥" }
        $body += "<div class='pst'><div class='title'>$t <a href='" + $p.Url + "'>" + $p.Title + "</a>$b</div>"
        $body += "<div class='meta'>" + $p.Author + " | " + $p.Replies + " 回复 | " + $p.Time + "</div></div>"
        $n++
    }
    $body += '</div>'
}

if ($hot.Count -gt 0) {
    $body += '<div class="sec"><h2>🔥 热门讨论</h2>'
    foreach ($p in $hot) {
        $t = ""
        if ($p.Category) { $t = "<span class='tag'>" + $p.Category + "</span>" }
        $body += "<div class='pst'><div class='title'>$t <a href='" + $p.Url + "'>" + $p.Title + "</a></div>"
        $body += "<div class='meta'><b>" + $p.Replies + " 回复</b> | " + $p.Author + " | " + $p.Time + "</div></div>"
    }
    $body += '</div>'
}

$body += @'
<div class="pri"><b>提示：</b>部分帖子需要回复后才可见商品链接，标 🔥 的热帖优先看。</div>
<div class="footer">由 OpenCode 自动生成</div>
</body></html>
'@

$out = Join-Path $PSScriptRoot ("briefing-" + $DateStr + ".html")
$body | Out-File $out -Encoding utf8
Write-Host ("Saved: " + $out)

if ($Test) {
    Write-Host "`n=== TEST MODE ==="
    Write-Host ("To: " + $Config.ToEmail)
    Write-Host ("$($priority.Count) priority, $($normal.Count) normal, $($hot.Count) hot")
} else {
    try {
        $s = New-Object Net.Mail.SmtpClient($Config.SmtpServer, $Config.SmtpPort)
        $s.EnableSsl = $true
        $s.Credentials = New-Object Net.NetworkCredential($Config.FromEmail, $Config.FromPassword)
        $m = New-Object Net.Mail.MailMessage
        $m.From = $Config.FromEmail; $m.To.Add($Config.ToEmail)
        $m.Subject = "今日薅羊毛简报 " + $DateStr; $m.Body = $body; $m.IsBodyHtml = $true
        $s.Send($m)
        Write-Host "Sent!"
    } catch { Write-Host ("FAIL: " + $_.Exception.Message) }
}
