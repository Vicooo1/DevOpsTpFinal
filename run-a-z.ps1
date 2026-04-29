param(
    [string]$RepoRoot = "C:\Users\kuchp\Documents\CIR3\DevOps\TP_Final",
    [string]$DockerImage = "vicopetit/api-lacets:latest",
    [string]$DbName = "lacets_db",
    [string]$DbUser = "api_user",
    [string]$DbPassword = "api_password"
)

$ErrorActionPreference = "Stop"

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

function Invoke-VagrantSsh {
    param([string]$Command)
    vagrant ssh -c $Command
}

Write-Step "0) Verification des prerequis"
Assert-Command "vagrant"
Assert-Command "docker"

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
vagrant up k3s
vagrant up monitoring

Write-Step "2) Installation K3s (idempotent)"
vagrant ssh k3s -c "command -v curl >/dev/null 2>&1 || (sudo apt-get update -y && sudo apt-get install -y curl)"
vagrant ssh k3s -c "command -v k3s >/dev/null 2>&1 || curl -sfL https://get.k3s.io | sh -"
vagrant ssh k3s -c "sudo /usr/local/bin/k3s kubectl get nodes"

Write-Step "3) Build image API"
Set-Location $AppDir
docker build -t $DockerImage .

Write-Step "4) Push image Docker"
docker push $DockerImage

Write-Step "5) Deploiement MySQL + API"
Set-Location $PrepInfraDir
$mysqlContent = Get-Content -Raw -Path $MysqlManifest
$apiContent = Get-Content -Raw -Path $ApiManifest

$mysqlContent | vagrant ssh k3s -c "cat > /tmp/mysql.yaml"
$apiContent | vagrant ssh k3s -c "cat > /tmp/api.yaml"

vagrant ssh k3s -c "sudo /usr/local/bin/k3s kubectl apply -f /tmp/mysql.yaml"
vagrant ssh k3s -c "sudo /usr/local/bin/k3s kubectl apply -f /tmp/api.yaml"

Write-Step "6) Mise a jour image de l'API"
vagrant ssh k3s -c "sudo /usr/local/bin/k3s kubectl set image deployment/api-lacets api-lacets=$DockerImage"

Write-Step "7) Attente du readiness"
vagrant ssh k3s -c "sudo /usr/local/bin/k3s kubectl rollout status deployment/mysql --timeout=240s"
vagrant ssh k3s -c "sudo /usr/local/bin/k3s kubectl rollout status deployment/api-lacets --timeout=240s"

Write-Step "8) Initialisation schema users"
$sql = "CREATE TABLE IF NOT EXISTS users (id VARCHAR(255) PRIMARY KEY, first_name VARCHAR(100) NOT NULL, last_name VARCHAR(100) NOT NULL, age INT NOT NULL);"
$initCmd = "sudo /usr/local/bin/k3s kubectl exec deploy/mysql -- mysql -u$DbUser -p$DbPassword $DbName -e `"$sql`""
vagrant ssh k3s -c $initCmd

Write-Step "9) Verification cluster"
vagrant ssh k3s -c "sudo /usr/local/bin/k3s kubectl get pods,svc,hpa"

Write-Step "10) Test API (port-forward dans une autre console)"
Write-Host "Lance cette commande dans un 2e terminal:" -ForegroundColor Yellow
Write-Host "  cd `"$PrepInfraDir`""
Write-Host "  vagrant ssh k3s -c 'sudo /usr/local/bin/k3s kubectl port-forward svc/api-lacets 3000:80'"
Write-Host ""
Write-Host "Puis teste depuis Windows:" -ForegroundColor Yellow
Write-Host "  curl http://localhost:3000/api"

Write-Step "Termine"
Write-Host "Execution complete." -ForegroundColor Green
