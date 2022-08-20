function CheckHeadersFile() {
    if ($env:HUGO_ENV -eq "production") {
        Write-Output "INFO: Production environment. Checking the _headers file for noindex headers."


        if (Select-String -Path "public/_headers" -Pattern "noindex") {
            Write-Output "PANIC: noindex headers were found in the _headers file. This build has failed."
            Exit 1
        }
        else {
            Write-Output "INFO: noindex headers were not found in the _headers file. All clear."
            Exit 0
        }
    }
    else {
        Write-Output "Non-production environment. Skipping the _headers file check."
        Exit 0
    }
}

CheckHeadersFile