$ErrorActionPreference='Stop'
$base='http://127.0.0.1:9000'
$evidence=Join-Path $PSScriptRoot '.'
$credentialFile='C:/Temp/sams-whitebox-tools/local-analysis-credential.xml'
if(Test-Path $credentialFile){
  $password=(Import-Clixml $credentialFile).GetNetworkCredential().Password
}else{
  $headers=@{Authorization='Basic '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:admin'))}
  $password='Wb!'+[Guid]::NewGuid().ToString('N')+'9a'
  Invoke-RestMethod -Uri "$base/api/users/change_password" -Method Post -Headers $headers -Body @{login='admin';previousPassword='admin';password=$password} | Out-Null
  [PSCredential]::new('admin',(ConvertTo-SecureString $password -AsPlainText -Force)) | Export-Clixml $credentialFile
}
$headers=@{Authorization='Basic '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:'+$password))}
# Temporary, loopback-only evaluation server. No remote publication.
Invoke-RestMethod -Uri "$base/api/settings/set" -Method Post -Headers $headers -Body @{key='sonar.forceAuthentication';value='false'} | Out-Null
$existing=Invoke-RestMethod -Uri "$base/api/projects/search?projects=sentinel-link-whitebox" -Headers $headers
if($existing.paging.total -eq 0){Invoke-RestMethod -Uri "$base/api/projects/create" -Method Post -Headers $headers -Body @{project='sentinel-link-whitebox';name='Sentinel Link White-Box Assessment';visibility='public'} | Out-Null}
Invoke-RestMethod -Uri "$base/api/system/status" -Headers $headers | ConvertTo-Json -Depth 10 | Set-Content "$evidence/server-status.json"
Invoke-RestMethod -Uri "$base/api/languages/list" -Headers $headers | ConvertTo-Json -Depth 10 | Set-Content "$evidence/languages.json"
$tokenName='whitebox-'+[Guid]::NewGuid().ToString('N')
$token=Invoke-RestMethod -Uri "$base/api/user_tokens/generate" -Method Post -Headers $headers -Body @{name=$tokenName;type='PROJECT_ANALYSIS_TOKEN';projectKey='sentinel-link-whitebox'}
$env:SONAR_TOKEN=$token.token
$env:SONAR_HOST_URL=$base
$env:JAVA_HOME='C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot'
$env:JAVA_TOOL_OPTIONS='-Djdk.net.unixdomain.tmpdir=C:/Temp/sams-whitebox-tools/sockets'
try {
  $properties=Get-Content "$PSScriptRoot/sonar-project.properties" | Where-Object { $_ -and !$_.StartsWith('#') } | ForEach-Object { '-D'+$_ }
  npx --yes @sonar/scan @properties '-Dsonar.scanner.skipJreProvisioning=true' '-Dsonar.scanner.javaExePath=C:/Program Files/Eclipse Adoptium/jdk-21.0.9.10-hotspot/bin/java.exe' '-Dsonar.qualitygate.wait=true' '-Dsonar.qualitygate.timeout=300' 1> "$evidence/scanner.log" 2> "$evidence/scanner.stderr.log"
  $LASTEXITCODE | Set-Content "$evidence/scanner.exitcode"
  $metrics='coverage,line_coverage,branch_coverage,lines_to_cover,uncovered_lines,conditions_to_cover,uncovered_conditions,bugs,vulnerabilities,code_smells,security_hotspots,duplicated_lines_density,duplicated_lines,ncloc,reliability_rating,security_rating,sqale_rating,alert_status'
  Invoke-RestMethod -Uri "$base/api/measures/component?component=sentinel-link-whitebox&metricKeys=$metrics" -Headers $headers | ConvertTo-Json -Depth 30 | Set-Content "$evidence/measures.json"
  Invoke-RestMethod -Uri "$base/api/qualitygates/project_status?projectKey=sentinel-link-whitebox" -Headers $headers | ConvertTo-Json -Depth 30 | Set-Content "$evidence/quality-gate.json"
  $page=1
  do {
    $issues=Invoke-RestMethod -Uri "$base/api/issues/search?componentKeys=sentinel-link-whitebox&ps=500&p=$page" -Headers $headers
    $issues | ConvertTo-Json -Depth 40 | Set-Content "$evidence/issues-$page.json"
    $page++
  } while (($page-1)*500 -lt $issues.total)
  Invoke-RestMethod -Uri "$base/api/hotspots/search?projectKey=sentinel-link-whitebox&ps=500" -Headers $headers | ConvertTo-Json -Depth 30 | Set-Content "$evidence/hotspots.json"
} finally {
  Invoke-RestMethod -Uri "$base/api/user_tokens/revoke" -Method Post -Headers $headers -Body @{name=$tokenName} | Out-Null
  Remove-Item Env:SONAR_TOKEN -ErrorAction SilentlyContinue
}
