$HUGO_VERSION = $($(Select-String -Pattern "^HUGO_VERSION" -Path "./netlify.toml" | Select-Object -Last 1 | Out-String).Split("=")[1]).Replace("""", "").Trim()
$NODE_BIN = "node_modules/.bin"
$NETLIFY_FUNC = "$NODE_BIN/netlify-lambda"

# The CONTAINER_ENGINE variable is used for specifying the container engine. By default 'docker' is used
# but this can be overridden when calling make, e.g.
# CONTAINER_ENGINE=podman make container-image
$CURDIR = $PSScriptRoot
$CONTAINER_ENGINE = "docker"
$IMAGE_REGISTRY = "gcr.io/k8s-staging-sig-docs"
$makeAndDockerfileStream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($(Get-Content -Path Dockerfile, Makefile -Raw)))
$IMAGE_VERSION = $(Get-FileHash -InputStream $makeAndDockerfileStream -Algorithm SHA256).Hash.ToString().Substring(0, 12)
$CONTAINER_IMAGE = "$IMAGE_REGISTRY/k8s-website-hugo:v$HUGO_VERSION-$IMAGE_VERSION"
$CONTAINER_RUN = "$CONTAINER_ENGINE run --rm --interactive --tty --volume ""$($CURDIR):/src"""

$CCRED = "`e[0;31m"
$CCEND = "`e[0m"

#.PHONY: all build build-preview help serve

## help: Show this help.
function help() {
    $currentScript = $PSCommandPath
    $content = Get-Content $currentScript -Raw
    $commentMatches = Select-String -InputObject $content -Pattern "##(\s*)(?<functionName>[a-zA-Z_][a-zA-Z0-9_-]*)\s*:(?<description>.*)" -AllMatches
    foreach ($match in $commentMatches.Matches) {
        $functionName = $match.Groups["functionName"].Value.Trim()
        $description = $match.Groups["description"].Value.Trim()
        $description = $description.Replace("\n", "\n{$([string]::Format("{0,22}", " "))")
        $formattedFunctionName = [string]::Format("{0,-20}", $functionName)
        Write-Host "`e[36m$formattedFunctionName`e[0m $description"
    }
}


## module-check: Check if all of the required submodules are correctly initialized.
function module-check() {
    $err = 0;
    git submodule status --recursive `
    | Select-String -Pattern "^[+-]" `
    | ForEach-Object {
        $err = 1
        $submodule = $_.Line.Split(" ")[1];
        Write-Output "`e[31mWARNING`e[0m Submodule not initialized: $($submodule)"
    }

    if ($err -ne 0) {
        Write-Output "You need to run `e[32m .\run_container_serve.ps1 module-init `e[0m to initialize missing modules first"
    }
}

## module-init: Initialize required submodules.
function module-init() {
    Write-Output "Initializing submodules..."
    git submodule update --init --recursive --depth 1
}

## all: Build site with production settings and put deliverables in ./public
function all() {
    build
}

## build: Build site with non-production settings and put deliverables in ./public
function build() {
    module-check
    hugo --minify --environment development
}

## build-preview: Build site with drafts and future posts enabled
function build-preview() {
    module-check
    hugo --buildDrafts --buildFuture --environment preview
}

## deploy-preview: Deploy preview site via netlify
function deploy-preview() {
    hugo --enableGitInfo --buildFuture --environment preview -b $(DEPLOY_PRIME_URL)
}

function functions-build() {
    & $NETLIFY_FUNC build functions-src
}

function check-headers-file() {
    . scripts/check-headers-file.ps1
}

## production-build: Build the production site and ensure that noindex headers aren't added
function production-build() {
    module-check
    hugo --minify --environment production
    $env:HUGO_ENV = production check-headers-file
}

## non-production-build: Build the non-production site, which adds noindex headers to prevent indexing
function non-production-build() {
    module-check
    hugo --enableGitInfo --environment nonprod
}

## serve: Boot the development server.
function serve() {
    module-check
    hugo server --buildFuture --environment development
}

function docker-image() {
    Write-Output "$CCRED**** The use of docker-image is deprecated. Use container-image instead. ****$CCEND"
    container-image
}

function docker-build() {
    Write-Output "$CCRED**** The use of docker-build is deprecated. Use container-build instead. ****$CCEND"
    container-build
}

function docker-serve() {
    Write-Output "$CCRED**** The use of docker-serve is deprecated. Use container-serve instead. ****$CCEND"
    container-serve
}

## container-image: Build a container image for the preview of the website
function container-image() {
    & $CONTAINER_ENGINE build . --network=host --tag $CONTAINER_IMAGE --build-arg HUGO_VERSION=$HUGO_VERSION
}

## container-push: Push container image for the preview of the website
function container-push() {
    container-image
    Invoke-Expression $CONTAINER_ENGINE push $CONTAINER_IMAGE
}

function container-build() {
    module-check
    $command = "$CONTAINER_RUN --read-only --mount type=tmpfs,destination=/tmp,tmpfs-mode=01777 $CONTAINER_IMAGE sh -c ""npm ci && hugo --minify --environment development"""
    Invoke-Expression $command
}

# no build lock to allow for read-only mounts
## container-serve: Boot the development server using container.
function container-serve() {
    module-check
    $command = "$CONTAINER_RUN --cap-drop=ALL --cap-add=AUDIT_WRITE --read-only --mount type=tmpfs,destination=/tmp,tmpfs-mode=01777 -p 1313:1313 $CONTAINER_IMAGE " +
    "hugo server --buildFuture --environment development --bind 0.0.0.0 --destination /tmp/hugo --cleanDestinationDir --noBuildLock"
    Invoke-Expression $command
}

function test-examples() {
    . scripts/test_examples.ps1 install
    . scripts/test_examples.ps1 run
}

# .PHONY: link-checker-setup
function link-checker-image-pull() {
    Invoke-Expression $CONTAINER_ENGINE pull wjdp/htmltest
}

function docker-internal-linkcheck() {
    Write-Output "$CCRED**** The use of docker-internal-linkcheck is deprecated. Use container-internal-linkcheck instead. ****$CCEND"
    container-internal-linkcheck
}

function container-internal-linkcheck() {
    link-checker-image-pull
    Invoke-Expression $CONTAINER_RUN $CONTAINER_IMAGE hugo --config config.toml, linkcheck-config.toml --buildFuture --environment test
    Invoke-Expression $CONTAINER_ENGINE run --mount "type=bind,source=$CURDIR,target=/test" --rm wjdp/htmltest htmltest
}

## clean-api-reference: Clean all directories in API reference directory, preserve _index.md
function clean-api-reference() {
    Remove-Item -Recurse -Force "content/en/docs/reference/kubernetes-api/*/"
}

## api-reference: Build the API reference pages. go needed
function api-reference() {
    clean-api-reference
    Set-Location api-ref-generator/gen-resourcesdocs
    go run cmd/main.go kwebsite --config-dir ../../api-ref-assets/config/ --file ../../api-ref-assets/api/swagger.json --output-dir ../../content/en/docs/reference/kubernetes-api --templates ../../api-ref-assets/templates
}



$cmd, $params = $args
& $cmd @params