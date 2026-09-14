$ErrorActionPreference="Stop"

$base=$PSScriptRoot
$channels=Join-Path $base "channels.xml"
$playlist=Join-Path $base "playlist.json"
$raw=Join-Path $base "epg_raw.xml"
$output=Join-Path $base "epg.xml"

function prop($o,$n){
    foreach($x in $n){
        $p=$o.PSObject.Properties|? Name -ieq $x|select -First 1
        if($p){return $p.Value}
    }
}

function norm($s){
    if(!$s){return ""}
    $s=$s.ToUpper()
    $s=$s-replace '^\s*[A-Z0-9_-]+\s*:\s*',''
    $s=$s-replace 'ᴿᴬᵂ|ᴴᴰ|\bRAW\b|\bLQ\b|\bUHD\b|\b4K\b|\bFHD\b|\bHD\b|\bSD\b',''
    ($s-replace '\s+',' ').Trim()
}

[xml]$c=gc $channels -Raw
$groups=@{}

foreach($x in @($c.channels.channel)){
    $groups[[string]$x.xmltv_id]=@{
        name=norm $x.'#text'
        streams=@()
    }
}

$j=gc $playlist -Raw|ConvertFrom-Json
$streams=if($j -is [array]){@($j)}else{
    $v=$null
    foreach($p in "channels","items","data","playlist"){
        $v=prop $j @($p)
        if($v -is [array]){break}
    }
    if($v -is [array]){@($v)}else{@($j)}
}

foreach($s in $streams){
    $n=norm (prop $s @("channel","name","channel_name","title"))
    foreach($id in $groups.Keys){
        if($n -eq $groups[$id].name){
            $groups[$id].streams+=$s
            break
        }
    }
}

if(Test-Path $raw){rm $raw -Force}

npm run grab -- `
    --channels="$channels" `
    --output="$raw" `
    --days=7 `
    --maxConnections=5

[xml]$e=gc $raw -Raw

$settings=New-Object System.Xml.XmlWriterSettings
$settings.Indent=$true
$settings.Encoding=New-Object System.Text.UTF8Encoding($false)
$w=[System.Xml.XmlWriter]::Create($output,$settings)

$w.WriteStartDocument()
$w.WriteStartElement("tv")

$m=@()

foreach($source in $e.tv.channel){
    $sid=[string]$source.id
    if(!$groups.ContainsKey($sid)){continue}

    foreach($s in $groups[$sid].streams){
        $name=prop $s @("channel","name","channel_name","title")
        $streamid=prop $s @("stream_id","id")
        $oid="IPTV_$streamid"

        $m+=[pscustomobject]@{s=$sid;o=$oid}

        $w.WriteStartElement("channel")
        $w.WriteAttributeString("id",$oid)
        $w.WriteStartElement("display-name")
        $w.WriteString($name)
        $w.WriteEndElement()
        $w.WriteEndElement()
    }
}

foreach($p in $e.tv.programme){
    foreach($x in $m|? s -eq $p.channel){
        $w.WriteStartElement("programme")

        foreach($a in $p.Attributes){
            if($a.Name-ne"channel"){
                $w.WriteAttributeString($a.Name,$a.Value)
            }
        }

        $w.WriteAttributeString("channel",$x.o)

        foreach($child in $p.ChildNodes){
            $child.WriteTo($w)
        }

        $w.WriteEndElement()
    }
}

$w.WriteEndElement()
$w.WriteEndDocument()
$w.Close()

rm $raw -Force

Write-Host "Klaar: $output"
