[CmdletBinding()]
param(
    [string]$Region = "eu-north-1",
    [string]$ExpectedAccount = "366314473733",
    [string]$Cluster = "dcc-testlab-cluster",
    [string]$DccService = "dcc-app-service",
    [string]$RunnerTaskDefinitionFamily = "dcc-diagnostic-runner"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-AwsJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $output = & aws @Arguments --region $Region --output json
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI read-only command failed: aws $($Arguments -join ' ')"
    }
    $text = $output -join [Environment]::NewLine
    if (-not $text.Trim()) {
        throw "AWS CLI returned an empty response: aws $($Arguments -join ' ')"
    }
    return ($text | ConvertFrom-Json)
}

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw $Message }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

Write-Host "DCC Stateless Run AWS Preflight" -ForegroundColor Cyan
Write-Host "Read-only checks only. No tasks are started and no AWS resources are changed."

$identity = Invoke-AwsJson @("sts", "get-caller-identity")
Assert-Condition ($identity.Account -eq $ExpectedAccount) "AWS account is $ExpectedAccount."
Write-Host "Principal ARN: $($identity.Arn)"
Write-Host "Region: $Region"

$serviceResponse = Invoke-AwsJson @("ecs", "describe-services", "--cluster", $Cluster, "--services", $DccService)
Assert-Condition ($serviceResponse.failures.Count -eq 0 -and $serviceResponse.services.Count -eq 1) "DCC ECS service exists in the expected cluster."
$service = $serviceResponse.services[0]
Assert-Condition ($service.status -eq "ACTIVE" -and $service.desiredCount -eq 1 -and $service.runningCount -eq 1 -and $service.pendingCount -eq 0) "DCC ECS service is stable at desired/running/pending = 1/1/0."

$taskArns = Invoke-AwsJson @("ecs", "list-tasks", "--cluster", $Cluster, "--service-name", $DccService, "--desired-status", "RUNNING")
Assert-Condition ($taskArns.Count -eq 1) "Exactly one running DCC task is registered."
$taskResponse = Invoke-AwsJson @("ecs", "describe-tasks", "--cluster", $Cluster, "--tasks", $taskArns[0])
Assert-Condition ($taskResponse.failures.Count -eq 0 -and $taskResponse.tasks.Count -eq 1) "DCC task details are readable."
$task = $taskResponse.tasks[0]
Assert-Condition ($task.lastStatus -eq "RUNNING") "DCC task is RUNNING."
Assert-Condition ($task.containers.Count -ge 1 -and $task.containers[0].lastStatus -eq "RUNNING" -and $task.containers[0].healthStatus -eq "HEALTHY") "DCC container is RUNNING and HEALTHY."

$networkDetails = @($task.attachments | ForEach-Object { $_.details })
$eniId = ($networkDetails | Where-Object { $_.name -eq "networkInterfaceId" } | Select-Object -First 1).value
Assert-Condition (-not [string]::IsNullOrWhiteSpace($eniId)) "DCC task ENI is discoverable."
$eniResponse = Invoke-AwsJson @("ec2", "describe-network-interfaces", "--network-interface-ids", $eniId)
$eni = $eniResponse.NetworkInterfaces[0]
Assert-Condition ([string]::IsNullOrWhiteSpace($eni.Association.PublicIp)) "DCC task ENI has no public IPv4 address."

$taskDefinitionResponse = Invoke-AwsJson @("ecs", "describe-task-definition", "--task-definition", $service.taskDefinition)
$container = $taskDefinitionResponse.taskDefinition.containerDefinitions | Where-Object { $_.name -eq "dcc-app" } | Select-Object -First 1
Assert-Condition ($null -ne $container) "Active DCC task definition contains the dcc-app container."
$environment = @{}
foreach ($item in $container.environment) { $environment[$item.name] = $item.value }
Assert-Condition ($environment["DCC_STATELESS_RUN_API_ENABLED"] -eq "false") "Stateless Run API remains disabled pending authentication/access control."
Assert-Condition ($environment["DCC_ECS_ASSIGN_PUBLIC_IP"] -eq "false") "Diagnostic runner is configured without a public IP."
Assert-Condition ($environment["DCC_RESULT_CALLBACK_BASE_URL"] -eq "http://dcc-app.dcc-test.internal:8000") "DCC callback base URL uses the private Cloud Map name."

$dccSecurityGroup = @($task.securityGroups)[0]
$runnerSecurityGroup = $environment["DCC_ECS_SECURITY_GROUPS"]
Assert-Condition (-not [string]::IsNullOrWhiteSpace($dccSecurityGroup) -and -not [string]::IsNullOrWhiteSpace($runnerSecurityGroup)) "DCC and diagnostic-runner security groups are configured."

$runnerDefinitionResponse = Invoke-AwsJson @("ecs", "describe-task-definition", "--task-definition", $RunnerTaskDefinitionFamily)
$runnerDefinition = $runnerDefinitionResponse.taskDefinition
$runnerContainer = $runnerDefinition.containerDefinitions | Where-Object { $_.name -eq "diagnostic-runner" } | Select-Object -First 1
Assert-Condition ($runnerDefinition.status -eq "ACTIVE" -and $runnerDefinition.requiresCompatibilities -contains "FARGATE" -and $runnerDefinition.networkMode -eq "awsvpc") "Dedicated runner task definition is ACTIVE, Fargate-compatible, and awsvpc."
Assert-Condition ($null -ne $runnerContainer -and $runnerContainer.user -eq "10001:10001") "Dedicated runner uses the non-root container identity."
Assert-Condition ($runnerContainer.command -contains "apps.diagnostics.runner") "Dedicated runner invokes the fixed runtime-health module."
Assert-Condition ($runnerDefinition.cpu -eq "256" -and $runnerDefinition.memory -eq "512") "Dedicated runner uses the bounded 256 CPU / 512 MiB task size."

$securityGroupsResponse = Invoke-AwsJson @("ec2", "describe-security-groups", "--group-ids", $dccSecurityGroup, $runnerSecurityGroup)
$groups = @{}
foreach ($group in $securityGroupsResponse.SecurityGroups) { $groups[$group.GroupId] = $group }
Assert-Condition ($groups.ContainsKey($dccSecurityGroup) -and $groups.ContainsKey($runnerSecurityGroup)) "Both expected security groups exist."
$ingressFromRunner = @($groups[$dccSecurityGroup].IpPermissions | Where-Object {
    $_.IpProtocol -eq "tcp" -and $_.FromPort -le 8000 -and $_.ToPort -ge 8000 -and
    @($_.UserIdGroupPairs | ForEach-Object { $_.GroupId }) -contains $runnerSecurityGroup
}).Count -gt 0
$egressToDcc = @($groups[$runnerSecurityGroup].IpPermissionsEgress | Where-Object {
    $_.IpProtocol -eq "tcp" -and $_.FromPort -le 8000 -and $_.ToPort -ge 8000 -and
    @($_.UserIdGroupPairs | ForEach-Object { $_.GroupId }) -contains $dccSecurityGroup
}).Count -gt 0
Assert-Condition $ingressFromRunner "DCC allows TCP 8000 ingress from the diagnostic-runner security group."
Assert-Condition $egressToDcc "Diagnostic runner allows TCP 8000 egress to the DCC security group."

$logGroups = Invoke-AwsJson @("logs", "describe-log-groups", "--log-group-name-prefix", "/ecs/dcc-testlab/diagnostic-runner")
Assert-Condition (@($logGroups.logGroups | Where-Object { $_.logGroupName -eq "/ecs/dcc-testlab/diagnostic-runner" }).Count -eq 1) "Dedicated diagnostic-runner log group exists."

Write-Host ""
Write-Host "PREFLIGHT=PASS" -ForegroundColor Green
Write-Host "No diagnostic task was started. No AWS resources were changed."
Write-Host "Keep the run API disabled until authentication or a private operator-only ingress boundary is implemented."
