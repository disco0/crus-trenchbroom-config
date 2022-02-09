#!pwsh
#Requires -Version 6

using namespace System.IO

[CmdletBinding()]
param()

function Get-ImportDepsPaths()
{
    [cmdletbinding()]
    [OutputType([String[]])]
    param(
        [Parameter(Mandatory, Position = 0)]
        $FilePath,
        $ProjectBase = "C:\csquad\project"
    )

    if(-not ([path]::IsPathRooted($FilePath)))
    {
        $importPath = [path]::Join($ProjectBase, [path]::GetRelativePath($ProjectBase, [path]::GetFullPath("$PWD\${FilePath}.import")))
    }
    else
    {
        $importPath  = [path]::GetFullPath("$FilePath.import")
    }

    Write-Verbose "Checking for import file $importPath"
    if(-not (Test-Path $importPath)) { return }

    @((Get-Content $ImportPath | Select-String '^dest_files') -replace '^dest_files=', '' | ConvertFrom-Json).
        ForEach{ [Path]::GetFullPath([Path]::Join($ProjectBase, $_ -Replace '^res:\/+', "")) }
}

# Via https://stackoverflow.com/a/69965594/12697514
function Copy-Folder
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$FromPath,

        [Parameter(Mandatory)]
        [String]$ToPath,

        [string[]] $Exclude
    )
    if (Test-Path $FromPath -PathType Container)
    {
        New-Item $ToPath -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
        @(Get-ChildItem $FromPath -Force).
            ForEach{
                # Avoid the nested pipeline variable
                $child = $_
                $target_path = Join-Path $ToPath $child.Name
                if (($Exclude | ForEach-Object { $child.Name -like $_ }) -notcontains $true)
                {
                    if (Test-Path $target_path)
                    {
                        Remove-Item $target_path -Recurse -Force
                    }

                    Copy-Item $child.FullName $target_path
                    Copy-Folder -FromPath $child.FullName -ToPath $target_path -Exclude:$Exclude
                }
            }
    }
}

function local:rebuild()
{
    $local:ErrorActionPreference = ([System.Management.Automation.ActionPreference]::Stop)

    $moddir = Get-Item "$PSScriptRoot"
    $modName = $moddir.basename
    $modJson = Get-Item $moddir\mod.json
    $tmpZipDirPath = "$ENV:TEMP\${modname}-zip"
    if (Test-Path $tmpZipDirPath) { Remove-Item -Force -Recurse -Verbose $tmpZipDirPath }
    mkdir $tmpZipDirPath
    $tmpZipDir = Get-Item $tmpZipDirPath
    $tmpZipModContentDir = "${tmpZipDir}\MOD_CONTENT\$modname"

    if(-not (Test-Path "$tmpZipDir\.import"))
    {
        mkdir "$tmpZipDir\.import"
    }

    $importFilePaths = @(Get-ChildItem -Recurse $moddir).
        Where{ $_.Extension -eq ".png" }.
        ForEach{
            Write-Host -F Cyan "Resolving imports for $_"
            Get-ImportDepsPaths -FilePath $_ -ProjectBase $projectDir
        } | Select-Object -Unique

    $importFilePaths.ForEach{
        if(Test-Path $_)
        {
            Write-Host "$($PSStyle.Magenta).import/$((Get-Item $_).Name)$($PSStyle.Reset)"
            Copy-Item $_ "$tmpZipDir\.import"
        }
        else
        {
            Write-Warning "Resolved dependency not found: $_"
        }
    }

    $customModInstallDir = "C:\csquad\user\mods\$modName"
    $modInstallDir =
        if(Test-Path $customModInstallDir -PathType Container)
        {
            $customModInstallDir
        }
        else # Default expected user path for windows
        {
            "$ENV:APPDATA\Godot\app_userdata\Cruelty Squad\mods\$modName"
        }

    if(Test-Path $modInstallDir)
    {
        if(Test-Path $modInstallDir -PathType Leaf)
        {
            throw "$modName install directory exists and is a file."
        }
    }
    else
    {
        mkdir $modInstallDir
    }

    [string[]] $copyExcludes = @(".git*", "media", "mod.zip", "mod.json", "README.md", "*.ps1", "$tmpZipDir" )

    Copy-Folder -Verbose -Exclude $copyExcludes -FromPath "$modDir" -ToPath "$tmpZipModContentDir"

    $modZipOutPath = "$modInstallDir\mod.zip"
    if (Test-Path $modZipOutPath) { Remove-Item -Verbose $modZipOutPath }

    [System.IO.Compression.ZipFile]::CreateFromDirectory($tmpZipdir, $modZipOutPath)
    Copy-Item -v -Force $modJSON $modInstallDir

    if (Test-Path $modZipOutPath)
    {
        Write-Host -ForegroundColor Green 'Complete.'
        Remove-Item -Recurse -Force -Verbose $tmpZipDir
    }
    else
    {
        Write-Error "Expected mod.zip not found: $($PSStyle.Underline)$modZipOutPath$($PSStyle.UnderlineOff)"
    }
}

rebuild