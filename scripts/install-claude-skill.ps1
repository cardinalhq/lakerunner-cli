#Requires -Version 5.1
# Copyright 2025-2026 CardinalHQ, Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Installs the lakerunner-cli Claude Code skill into %USERPROFILE%\.claude\skills\.
#
# Usage (from a checkout):
#   pwsh scripts\install-claude-skill.ps1
#
# Usage (one-liner, no checkout):
#   iex (irm https://raw.githubusercontent.com/cardinalhq/lakerunner-cli/main/scripts/install-claude-skill.ps1)

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SkillName = 'lakerunner-cli'
$SkillUrl  = "https://raw.githubusercontent.com/cardinalhq/lakerunner-cli/main/.claude/skills/$SkillName/SKILL.md"

$SkillsRoot = if ($env:CLAUDE_SKILLS_DIR) {
    $env:CLAUDE_SKILLS_DIR
} else {
    Join-Path $env:USERPROFILE '.claude\skills'
}
$TargetDir  = Join-Path $SkillsRoot $SkillName
$TargetFile = Join-Path $TargetDir  'SKILL.md'

# Prefer a local copy when running from a checkout; otherwise fetch.
$LocalSkill = $null
if ($PSCommandPath) {
    $candidate = Join-Path (Split-Path -Parent $PSCommandPath) "..\.claude\skills\$SkillName\SKILL.md"
    if (Test-Path -LiteralPath $candidate) {
        $LocalSkill = (Resolve-Path -LiteralPath $candidate).Path
    }
}

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

if ($LocalSkill) {
    Copy-Item -LiteralPath $LocalSkill -Destination $TargetFile -Force
    Write-Host "Installed $SkillName skill from local checkout -> $TargetFile"
} else {
    # -UseBasicParsing keeps this working on Windows PowerShell 5.1 without IE.
    Invoke-WebRequest -Uri $SkillUrl -OutFile $TargetFile -UseBasicParsing
    Write-Host "Installed $SkillName skill from $SkillUrl -> $TargetFile"
}

function Test-Interactive {
    try {
        return (-not [Console]::IsInputRedirected) -and [Environment]::UserInteractive
    } catch {
        return $false
    }
}

function Read-SecureText {
    param([string]$Prompt)
    $secure = Read-Host -Prompt $Prompt -AsSecureString
    if ($null -eq $secure -or $secure.Length -eq 0) { return '' }
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Read-Credential {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$ExistingValue,
        [switch]$Secret
    )
    $suffix = ''
    if ($ExistingValue) {
        if ($Secret) {
            $tail = if ($ExistingValue.Length -ge 4) {
                $ExistingValue.Substring($ExistingValue.Length - 4)
            } else {
                $ExistingValue
            }
            $suffix = " [****$tail]"
        } else {
            $suffix = " [$ExistingValue]"
        }
    }
    $prompt = "  $Name$suffix"
    $value = if ($Secret) { Read-SecureText -Prompt $prompt } else { Read-Host -Prompt $prompt }
    if (-not $value) { return $ExistingValue }
    return $value
}

$credsDone = $false
if (Test-Interactive) {
    Write-Host ''
    Write-Host 'Configure Lakerunner credentials for the skill.'
    Write-Host "Get these from whoever runs your Lakerunner deployment (or the deployment's"
    Write-Host 'own docs/console). Leave blank to skip and set them yourself later.'
    Write-Host ''

    $url = Read-Credential -Name 'LAKERUNNER_QUERY_URL' -ExistingValue $env:LAKERUNNER_QUERY_URL
    $key = Read-Credential -Name 'LAKERUNNER_API_KEY'   -ExistingValue $env:LAKERUNNER_API_KEY -Secret

    if ($url -or $key) {
        Write-Host ''
        $answer = Read-Host 'Persist these to your user environment (via setx)? [y/N]'
        if ($answer -match '^[Yy]') {
            if ($url) {
                [Environment]::SetEnvironmentVariable('LAKERUNNER_QUERY_URL', $url, 'User')
                $env:LAKERUNNER_QUERY_URL = $url
            }
            if ($key) {
                [Environment]::SetEnvironmentVariable('LAKERUNNER_API_KEY', $key, 'User')
                $env:LAKERUNNER_API_KEY = $key
            }
            Write-Host 'Saved to your user environment. Open a new shell to pick up the values in child processes.'
        } else {
            Write-Host 'Skipped. To set them yourself:'
            if ($url) { Write-Host "  setx LAKERUNNER_QUERY_URL `"$url`"" }
            if ($key) { Write-Host '  setx LAKERUNNER_API_KEY "<your-key>"' }
        }
        $credsDone = $true
    }
}

Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Make sure lakerunner-cli is on your PATH.'
if (-not $credsDone) {
    Write-Host '  2. Set LAKERUNNER_QUERY_URL and LAKERUNNER_API_KEY in your environment'
    Write-Host '     (values come from your Lakerunner deployment - ask whoever runs it).'
    Write-Host "  3. In Claude Code, type /$SkillName to invoke the skill."
} else {
    Write-Host "  2. In Claude Code, type /$SkillName to invoke the skill."
}

Write-Host ''
Write-Host "Uninstall with: Remove-Item -Recurse -Force `"$TargetDir`""
