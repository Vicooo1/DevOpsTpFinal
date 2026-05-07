param(
    [string]$RepoRoot = "C:\Users\kuchp\Documents\CIR3\DevOps\TP_Final",
    [string]$DockerImage = "vicopetit/api-lacets:latest",
    [string]$DbName = "lacets_db",
    [string]$DbUser = "api_user",
    [string]$DbPassword = "api_password",
    [switch]$WithMonitoring
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSNativeCommandUseErrorActionPreference = $true
}


function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function Assert-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Commande manquante: $Name"
    }
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $false)][string[]]$Arguments = @()
    )
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Commande echouee: $Command $($Arguments -join ' ')"
    }
}

function Invoke-VagrantSsh {
    param([string]$Command)
    Push-Location $PrepInfraDir
    try {
        vagrant ssh k3s -c $Command
    }
    finally {
        Pop-Location
    }
}

function Invoke-Vagrant {
    param([string]$VagrantArgs)
    Push-Location $PrepInfraDir
    try {
        Invoke-Expression "vagrant $VagrantArgs"
    }
    finally {
        Pop-Location
    }
}

function Assert-DockerDaemon {
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker daemon indisponible. Demarre Docker Desktop puis relance le script."
    }
}

Write-Step "0) Verification des prerequis"
Assert-Command "vagrant"
Assert-Command "docker"
Assert-DockerDaemon

if (-not (Test-Path $RepoRoot)) {
    throw "Le dossier repo n'existe pas: $RepoRoot"
}

$PrepInfraDir = Join-Path $RepoRoot "prep_infra"
$AppDir = Join-Path $RepoRoot "app"
$K8sDir = Join-Path $RepoRoot "k8s"
$MysqlManifest = Join-Path $K8sDir "mysql.yaml"
$ApiManifest = Join-Path $K8sDir "api.yaml"

if (-not (Test-Path $PrepInfraDir)) { throw "Dossier introuvable: $PrepInfraDir" }
if (-not (Test-Path $AppDir)) { throw "Dossier introuvable: $AppDir" }
if (-not (Test-Path $MysqlManifest)) { throw "Fichier introuvable: $MysqlManifest" }
if (-not (Test-Path $ApiManifest)) { throw "Fichier introuvable: $ApiManifest" }

Write-Step "1) Demarrage VM"
Set-Location $PrepInfraDir
Invoke-Vagrant "up k3s"
if ($WithMonitoring) {
    Invoke-Vagrant "up monitoring"
}
else {
    # Mode leger local: on evite de consommer RAM/CPU avec la VM monitoring.
    Invoke-Vagrant "halt monitoring --force"
}

Write-Step "2) Installation K3s (idempotent)"
Invoke-Vagrant "ssh k3s -c `"command -v curl >/dev/null 2>&1 || (sudo apt-get update -y && sudo apt-get install -y curl)`""
Invoke-Vagrant "ssh k3s -c `"command -v k3s >/dev/null 2>&1 || curl -sfL https://get.k3s.io | sh -`""
Invoke-Vagrant "ssh k3s -c `"sudo /usr/local/bin/k3s kubectl get nodes`""

Write-Step "3) Build image API"
Set-Location $AppDir
docker build -t $DockerImage .

Write-Step "4) Push image Docker"
docker push $DockerImage

Write-Step "5) Deploiement MySQL + API"
Set-Location $PrepInfraDir
Invoke-Vagrant "upload `"$MysqlManifest`" /tmp/mysql.yaml k3s"
Invoke-Vagrant "upload `"$ApiManifest`" /tmp/api.yaml k3s"

Invoke-Vagrant "ssh k3s -c `"sudo /usr/local/bin/k3s kubectl apply -f /tmp/mysql.yaml`""
Invoke-Vagrant "ssh k3s -c `"sudo /usr/local/bin/k3s kubectl apply -f /tmp/api.yaml`""

Write-Step "6) Mise a jour image de l'API"
Invoke-Vagrant "ssh k3s -c `"sudo /usr/local/bin/k3s kubectl set image deployment/api-lacets api-lacets=$DockerImage`""

Write-Step "7) Attente du readiness"
Invoke-Vagrant "ssh k3s -c `"sudo /usr/local/bin/k3s kubectl rollout status deployment/mysql --timeout=240s`""
Invoke-Vagrant "ssh k3s -c `"sudo /usr/local/bin/k3s kubectl rollout status deployment/api-lacets --timeout=240s`""

Write-Step "8) Initialisation schema users"
$sql = "CREATE TABLE IF NOT EXISTS users (id VARCHAR(255) PRIMARY KEY, first_name VARCHAR(100) NOT NULL, last_name VARCHAR(100) NOT NULL, age INT NOT NULL);"
$initCmd = "sudo /usr/local/bin/k3s kubectl exec deploy/mysql -- mysql -u$DbUser -p$DbPassword $DbName -e `"$sql`""
Invoke-Vagrant "ssh k3s -c `"$initCmd`""

Write-Step "9) Verification cluster"
Invoke-Vagrant "ssh k3s -c `"sudo /usr/local/bin/k3s kubectl get pods,svc,hpa`""

Write-Step "10) Test API (port-forward dans une autre console)"
Write-Host "Lance cette commande dans un 2e terminal:" -ForegroundColor Yellow
Write-Host "  cd `"$PrepInfraDir`""
Write-Host "  vagrant ssh k3s -c 'sudo /usr/local/bin/k3s kubectl port-forward svc/api-lacets 3000:80'"
Write-Host ""
Write-Host "Puis teste depuis Windows:" -ForegroundColor Yellow
Write-Host "  curl http://localhost:3000/api"

Write-Step "Termine"
Write-Host "Execution complete." -ForegroundColor Green
