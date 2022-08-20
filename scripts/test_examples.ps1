
# List files changed in the commit to check
$FILES = $( git diff "$( git merge-base --fork-point master )" --name-only )

$TEST_EXAMPLES = "No"

# Check if examples folders (all locales) change in this branch
if ($FILES | Select-String -Pattern "^""?content/[^/]+/examples/") {
    $TEST_EXAMPLES = "Yes"
}

function install() {
    if ($TEST_EXAMPLES -ne "Yes") {
        Write-Output "PR not touching examples, skipping example tests install"
        Exit 0
    }

    $env:PATH = "$env:GOPATH/bin:$env:PATH"
    New-Item -ItemType Directory -Path "$env:HOME/gopath/src/k8s.io"
    Move-Item -Path $env:TRAVIS_BUILD_DIR -Destination "$env:HOME/gopath/src/k8s.io/website"
    Set-Location "$env:HOME/gopath/src/k8s.io/website"

    # Make sure we are testing against the correct branch
    $previousPWD = $PWD
    Set-Location "$env:GOPATH/src/k8s.io"
    Invoke-WebRequest -Uri "https://github.com/kubernetes/kubernetes/archive/v$KUBE_VERSION.0.tar.gz"
    Set-Location $previousPWD

    Push-Location "$env:GOPATH/src/k8s.io"
    tar xzf v$KUBE_VERSION.0.tar.gz
    Move-Item -Path "kubernetes-$KUBE_VERSION.0" -Destination "kubernetes"
    Set-Location "kubernetes"
    make generated_files
    Copy-Item -Recurse -Path "vendor" -Destination "$env:GOPATH/src/"
    Remove-Item -Recurse -Path "vendor"
    Pop-Location

    # Fetch additional dependencies to run the tests in examples/examples_test.go
    go get -t -v k8s.io/website/content/en/examples
}

function run_test() {
    if ($TEST_EXAMPLES -ne "Yes") {
        Write-Output "PR not touching examples, skipping example tests execution"
        Exit 0
    }
    go test -v k8s.io/website/content/en/examples
}

if ($args[0] -eq "install") {
    install
    Exit 0
}
elseif ($args[0] -eq "run") {
    run_test
}
