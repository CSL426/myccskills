Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ExcludedLeafNames = @(
    '.credentials.json',
    'auth.json',
    'oauth_creds.json',
    'google_accounts.json',
    'trustedFolders.json'
)
$script:BackupKeep = 5
$script:BackupOwnershipMarker = '.ai-config-backup-owned'
$script:BackupOwnershipValue = 'ai-config-backup-v1'

function Show-Usage {
    Write-Output 'ai-config - Cross-AI tool configuration manager'
    Write-Output ''
    Write-Output 'Usage:'
    Write-Output '  .\ai-config.ps1 <command> [tool]'
    Write-Output ''
    Write-Output 'Commands:'
    Write-Output '  init [tool]     Gather configs from tool home directories into ai-config/'
    Write-Output '  apply [tool]    Deploy configs from ai-config/ to tool home directories'
    Write-Output '  project [tool]  Project directly from ~/.claude/ to other tool home dirs'
    Write-Output '  status [tool]   Show diff between ai-config/ and current tool configs'
    Write-Output '  list            List managed tools and file counts'
    Write-Output '  reset           Clear all configs, leave empty skeleton'
    Write-Output ''
    Write-Output 'Tools:'
    Write-Output '  claude          Claude Code (~/.claude/)'
    Write-Output '  codex           Codex CLI (~/.codex/)'
    Write-Output '  agy             Antigravity CLI (~/.gemini/antigravity-cli/)'
    Write-Output '  all             All supported tools (default)'
}

function Resolve-Tool {
    param([string]$Name)

    if ([string]::IsNullOrEmpty($Name)) {
        return 'all'
    }

    switch ($Name) {
        'claude' { return 'claude' }
        'codex' { return 'codex' }
        'agy' { return 'agy' }
        'antigravity' { return 'agy' }
        'antigravity-cli' { return 'agy' }
        'antigravity_cli' { return 'agy' }
        'all' { return 'all' }
        default { throw "Unknown tool: $Name" }
    }
}

function Get-SelectedTools {
    param(
        [string]$Tool,
        [string[]]$AllTools
    )

    if ($Tool -eq 'all') {
        return $AllTools
    }
    return @($Tool)
}

function Get-UserHome {
    if (-not [string]::IsNullOrWhiteSpace([string]$HOME)) {
        return [string]$HOME
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$env:USERPROFILE)) {
        return [string]$env:USERPROFILE
    }
    return [Environment]::GetFolderPath('UserProfile')
}

function Get-PathComparison {
    if ($env:OS -eq 'Windows_NT') {
        return [StringComparison]::OrdinalIgnoreCase
    }
    return [StringComparison]::Ordinal
}

function New-Directory {
    param([string]$Path)

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $null = New-Item -ItemType Directory -Path $Path -Force
    }
}

function Test-ExcludedLeafName {
    param([string]$Name)

    return $script:ExcludedLeafNames -contains $Name
}

function Test-SafeLeafName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }
    if ($Name -eq '.' -or $Name -eq '..' -or $Name -match '[/\\]') {
        return $false
    }
    if ($Name -match '^[A-Za-z]:' -or [IO.Path]::IsPathRooted($Name)) {
        return $false
    }
    return [IO.Path]::GetFileName($Name) -eq $Name
}

function Get-ContainedChildPath {
    param(
        [string]$Parent,
        [string]$Name
    )

    if (-not (Test-SafeLeafName $Name)) {
        throw "Unsafe leaf name: $Name"
    }
    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $childFull = [IO.Path]::GetFullPath((Join-Path $parentFull $Name))
    $prefix = $parentFull + [IO.Path]::DirectorySeparatorChar
    if (-not $childFull.StartsWith($prefix, (Get-PathComparison))) {
        throw "Path escapes managed root: $Name"
    }
    return $childFull
}

function Get-PathItem {
    param([string]$Path)

    return Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Test-IsReparsePoint {
    param([string]$Path)

    $item = Get-PathItem $Path
    if ($null -eq $item) {
        return $false
    }
    return ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
}

function Assert-NoReparsePoints {
    param([string]$Path)

    $item = Get-PathItem $Path
    if ($null -eq $item) {
        return
    }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing reparse point in managed path: $Path"
    }
    if (-not $item.PSIsContainer) {
        return
    }
    foreach ($child in Get-ChildItem -LiteralPath $Path -Force -Recurse) {
        if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing reparse point in managed path: $($child.FullName)"
        }
    }
}

function Assert-SafeWriteTarget {
    param([string]$Path)

    if (Test-IsReparsePoint $Path) {
        throw "Refusing reparse point file destination: $Path"
    }
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and (Test-IsReparsePoint $parent)) {
        throw "Refusing reparse point parent destination: $parent"
    }
}

function Get-ReparseTargetFullPath {
    param([string]$Path)

    $item = Get-PathItem $Path
    if ($null -eq $item -or -not (Test-IsReparsePoint $Path)) {
        return ''
    }
    $targetProperty = $item.PSObject.Properties['Target']
    if ($null -eq $targetProperty -or $null -eq $targetProperty.Value) {
        return ''
    }
    $target = [string]@($targetProperty.Value)[0]
    if (-not [IO.Path]::IsPathRooted($target)) {
        $target = Join-Path (Split-Path -Parent $Path) $target
    }
    return [IO.Path]::GetFullPath($target)
}

function Assert-ReparseTarget {
    param(
        [string]$Path,
        [string]$ExpectedTarget
    )

    $actual = Get-ReparseTargetFullPath $Path
    $expected = [IO.Path]::GetFullPath($ExpectedTarget)
    if (-not [string]::Equals($actual, $expected, (Get-PathComparison))) {
        throw "Reparse point target mismatch: $Path"
    }
}

function Copy-File {
    param(
        [string]$Source,
        [string]$Destination
    )

    Assert-NoReparsePoints $Source
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        return
    }
    if (Test-ExcludedLeafName ([IO.Path]::GetFileName($Source))) {
        return
    }

    Assert-SafeWriteTarget $Destination
    New-Directory (Split-Path -Parent $Destination)
    [IO.File]::Copy(
        (Get-Item -LiteralPath $Source).FullName,
        $Destination,
        $true
    )
}

function Copy-PathRaw {
    param(
        [string]$Source,
        [string]$Destination
    )

    Assert-NoReparsePoints $Source
    if (Test-Path -LiteralPath $Source -PathType Leaf) {
        if (Test-ExcludedLeafName ([IO.Path]::GetFileName($Source))) {
            return
        }
        New-Directory (Split-Path -Parent $Destination)
        [IO.File]::Copy(
            (Get-Item -LiteralPath $Source).FullName,
            $Destination,
            $true
        )
        return
    }
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }
    $sourceRoot = (Get-Item -LiteralPath $Source).FullName.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force) {
        if (Test-ExcludedLeafName $file.Name) {
            continue
        }
        $relativePath = $file.FullName.Substring($sourceRoot.Length).TrimStart(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        )
        $target = Join-Path $Destination $relativePath
        New-Directory (Split-Path -Parent $target)
        [IO.File]::Copy($file.FullName, $target, $true)
    }
}

function Copy-DirectoryOverlay {
    param(
        [string]$Source,
        [string]$Destination
    )

    Assert-NoReparsePoints $Source
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }

    $sourceRoot = (Get-Item -LiteralPath $Source).FullName.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -File -Recurse) {
        if (Test-ExcludedLeafName $file.Name) {
            continue
        }
        $relativePath = $file.FullName.Substring($sourceRoot.Length).TrimStart(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        )
        Copy-File $file.FullName (Join-Path $Destination $relativePath)
    }
}

function Sync-DirectoryMirror {
    param(
        [string]$Source,
        [string]$Destination
    )

    Assert-NoReparsePoints $Source
    Assert-NoReparsePoints $Destination
    $sourceFiles = @{}
    if (Test-Path -LiteralPath $Source -PathType Container) {
        $sourceRoot = (Get-Item -LiteralPath $Source).FullName.TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        )
        foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -File -Recurse) {
            if (Test-ExcludedLeafName $file.Name) {
                continue
            }
            $relativePath = $file.FullName.Substring($sourceRoot.Length).TrimStart(
                [IO.Path]::DirectorySeparatorChar,
                [IO.Path]::AltDirectorySeparatorChar
            )
            $sourceFiles[$relativePath] = $true
        }
    }

    if (Test-Path -LiteralPath $Destination -PathType Container) {
        $destinationRoot = (Get-Item -LiteralPath $Destination).FullName.TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        )
        foreach ($file in Get-ChildItem -LiteralPath $destinationRoot -File -Recurse) {
            if (Test-ExcludedLeafName $file.Name) {
                continue
            }
            $relativePath = $file.FullName.Substring($destinationRoot.Length).TrimStart(
                [IO.Path]::DirectorySeparatorChar,
                [IO.Path]::AltDirectorySeparatorChar
            )
            if (-not $sourceFiles.ContainsKey($relativePath)) {
                Remove-Item -LiteralPath $file.FullName -Force
            }
        }
        $directories = Get-ChildItem -LiteralPath $destinationRoot -Directory -Recurse |
            Sort-Object { $_.FullName.Length } -Descending
        foreach ($directory in $directories) {
            $child = Get-ChildItem -LiteralPath $directory.FullName -Force |
                Select-Object -First 1
            if ($null -eq $child) {
                Remove-Item -LiteralPath $directory.FullName -Force
            }
        }
    }

    Copy-DirectoryOverlay $Source $Destination
}

function Test-DirectoryHasFiles {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $false
    }
    $file = Get-ChildItem -LiteralPath $Path -File -Recurse |
        Select-Object -First 1
    return $null -ne $file
}

function Get-ToolLiveDirectory {
    param(
        [string]$Tool,
        [string]$HomeDirectory
    )

    switch ($Tool) {
        'claude' { return Join-Path $HomeDirectory '.claude' }
        'codex' { return Join-Path $HomeDirectory '.codex' }
        'agy' { return Join-Path $HomeDirectory '.gemini/antigravity-cli' }
    }
    throw "Unknown tool: $Tool"
}

function Get-ManagedBackupPaths {
    param([string]$Tool)

    switch ($Tool) {
        'claude' {
            return @(
                'CLAUDE.md', 'mcp.json', 'settings.json', 'statusline.sh',
                'rules', 'agents', 'commands'
            )
        }
        'codex' {
            return @('AGENTS.md', 'config.toml', 'rules', 'skills')
        }
        'agy' {
            return @('mcp_config.json', 'settings.json', 'skills', 'plugins')
        }
    }
    throw "Unknown tool: $Tool"
}

function Get-ManagedBackupSource {
    param(
        [string]$Tool,
        [string]$RelativePath,
        [string]$HomeDirectory
    )

    if ($Tool -eq 'agy' -and $RelativePath -eq 'skills') {
        $canonicalSkills = Join-Path $HomeDirectory '.gemini/antigravity/skills'
        if (Test-Path -LiteralPath $canonicalSkills) {
            return $canonicalSkills
        }
    }
    return Join-Path (
        Get-ToolLiveDirectory $Tool $HomeDirectory
    ) $RelativePath
}

function Enter-ApplyLock {
    param([string]$HomeDirectory)

    $backupRoot = Join-Path $HomeDirectory '.ai-config-backup'
    if (Test-IsReparsePoint $backupRoot) {
        throw "Refusing reparse point backup root: $backupRoot"
    }
    New-Directory $backupRoot
    $lockPath = Join-Path $backupRoot '.ai-config-backup.lock'
    Assert-SafeWriteTarget $lockPath
    for ($attempt = 0; $attempt -lt 200; $attempt++) {
        try {
            return [IO.File]::Open(
                $lockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None
            )
        }
        catch [IO.IOException] {
            Start-Sleep -Milliseconds 50
        }
    }
    throw "Timed out waiting for apply lock: $lockPath"
}

function Get-CompletedBackupSnapshots {
    param([string]$BackupRoot)

    $completed = New-Object Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) {
        return $completed
    }
    foreach ($directory in Get-ChildItem -LiteralPath $BackupRoot -Directory -Force) {
        if ($directory.Name -notmatch '^\d{4}-\d{2}-\d{2}-\d{9}$') {
            continue
        }
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Write-Warning "Ignoring reparse point backup directory: $($directory.FullName)"
            continue
        }
        $marker = Join-Path $directory.FullName $script:BackupOwnershipMarker
        if (
            -not (Test-Path -LiteralPath $marker -PathType Leaf) -or
            (Test-IsReparsePoint $marker)
        ) {
            continue
        }
        if ([IO.File]::ReadAllText($marker).Trim() -ne $script:BackupOwnershipValue) {
            continue
        }
        $completed.Add($directory)
    }
    return $completed
}

function Remove-OldBackupSnapshots {
    param([string]$HomeDirectory)

    $backupRoot = Join-Path $HomeDirectory '.ai-config-backup'
    $snapshots = @(
        Get-CompletedBackupSnapshots $backupRoot |
            Sort-Object Name -Descending
    )
    foreach ($oldSnapshot in ($snapshots | Select-Object -Skip $script:BackupKeep)) {
        try {
            Assert-NoReparsePoints $oldSnapshot.FullName
            Remove-Item -LiteralPath $oldSnapshot.FullName -Recurse -Force
        }
        catch {
            Write-Warning "Could not prune owned backup snapshot: $($oldSnapshot.FullName)"
        }
    }
}

function New-BackupSnapshot {
    param(
        [string[]]$Tools,
        [string]$HomeDirectory
    )

    $hasManagedContent = $false
    foreach ($tool in $Tools) {
        foreach ($relativePath in (Get-ManagedBackupPaths $tool)) {
            $source = Get-ManagedBackupSource $tool $relativePath $HomeDirectory
            if (Test-Path -LiteralPath $source) {
                $hasManagedContent = $true
                break
            }
        }
        if ($hasManagedContent) {
            break
        }
    }
    if (-not $hasManagedContent) {
        return
    }

    $backupRoot = Join-Path $HomeDirectory '.ai-config-backup'
    $temporarySnapshot = Join-Path (
        $backupRoot
    ) ('.tmp-' + [Guid]::NewGuid().ToString('N'))
    New-Directory $temporarySnapshot
    try {
        foreach ($tool in $Tools) {
            foreach ($relativePath in (Get-ManagedBackupPaths $tool)) {
                $source = Get-ManagedBackupSource $tool $relativePath $HomeDirectory
                if (Test-Path -LiteralPath $source) {
                    Copy-PathRaw $source (
                        Join-Path (Join-Path $temporarySnapshot $tool) $relativePath
                    )
                }
            }
        }
        Write-Utf8File (
            Join-Path $temporarySnapshot $script:BackupOwnershipMarker
        ) ($script:BackupOwnershipValue + "`n")
        do {
            $timestamp = Get-Date -Format 'yyyy-MM-dd-HHmmssfff'
            $snapshot = Join-Path $backupRoot $timestamp
            if (Test-Path -LiteralPath $snapshot) {
                Start-Sleep -Milliseconds 1
            }
        } while (Test-Path -LiteralPath $snapshot)
        [IO.Directory]::Move($temporarySnapshot, $snapshot)
        $temporarySnapshot = ''
    }
    finally {
        if (
            -not [string]::IsNullOrWhiteSpace($temporarySnapshot) -and
            (Test-Path -LiteralPath $temporarySnapshot)
        ) {
            try {
                Assert-NoReparsePoints $temporarySnapshot
                Remove-Item -LiteralPath $temporarySnapshot -Recurse -Force
            }
            catch {
                Write-Warning "Could not clean temporary backup: $temporarySnapshot"
            }
        }
    }
}

function Assert-ToolDestinationsSafe {
    param(
        [string[]]$Tools,
        [string]$HomeDirectory
    )

    foreach ($tool in $Tools) {
        $liveDirectory = Get-ToolLiveDirectory $tool $HomeDirectory
        if (Test-IsReparsePoint $liveDirectory) {
            throw "Refusing reparse point tool home: $liveDirectory"
        }
        switch ($tool) {
            'claude' {
                foreach ($name in @('CLAUDE.md', 'mcp.json', 'settings.json', 'statusline.sh')) {
                    Assert-SafeWriteTarget (Join-Path $liveDirectory $name)
                }
                foreach ($name in @('rules', 'agents', 'commands')) {
                    Assert-NoReparsePoints (Join-Path $liveDirectory $name)
                }
            }
            'codex' {
                foreach ($name in @('AGENTS.md', 'config.toml')) {
                    Assert-SafeWriteTarget (Join-Path $liveDirectory $name)
                }
                foreach ($name in @('rules', 'skills')) {
                    Assert-NoReparsePoints (Join-Path $liveDirectory $name)
                }
                Assert-CodexFallbackDestinationsSafe $HomeDirectory
            }
            'agy' {
                foreach ($name in @('mcp_config.json', 'settings.json')) {
                    Assert-SafeWriteTarget (Join-Path $liveDirectory $name)
                }
                Assert-NoReparsePoints (Join-Path $liveDirectory 'plugins')
                Assert-NoReparsePoints (
                    Join-Path $HomeDirectory '.gemini/antigravity/skills'
                )
                Assert-AgyFallbackDestinationSafe $HomeDirectory
            }
        }
    }
}

function Write-Utf8File {
    param(
        [string]$Path,
        [string]$Content
    )

    Assert-SafeWriteTarget $Path
    New-Directory (Split-Path -Parent $Path)
    $encoding = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Content, $encoding)
}

function ConvertTo-YamlScalar {
    param([string]$Value)

    return "'" + $Value.Replace("'", "''") + "'"
}

function ConvertTo-SkillDocument {
    param(
        [string]$Content,
        [string]$DefaultName
    )

    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n")
    $lines = [regex]::Split($normalized, "`n")
    if ($lines.Count -lt 2 -or $lines[0] -ne '---') {
        $name = $DefaultName
        $heading = [regex]::Match($normalized, '(?m)^#\s+(.+)$')
        if ($heading.Success) {
            $name = $heading.Groups[1].Value.Trim()
        }
        $nameScalar = ConvertTo-YamlScalar $name
        return (
            "---`nname: $nameScalar`ndescription: >-`n  $name`nmetadata:`n" +
            "  short-description: $nameScalar`n---`n$normalized"
        )
    }

    $closingFence = -1
    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -eq '---') {
            $closingFence = $index
            break
        }
    }
    if ($closingFence -lt 0) {
        throw "Invalid YAML frontmatter for skill: $DefaultName"
    }

    $frontmatter = New-Object Collections.Generic.List[string]
    for ($index = 1; $index -lt $closingFence; $index++) {
        $frontmatter.Add($lines[$index])
    }

    $name = $DefaultName
    $description = ''
    $hasName = $false
    $hasDescription = $false
    $hasMetadata = $false
    $hasShortDescription = $false
    $metadataIndex = -1
    for ($index = 0; $index -lt $frontmatter.Count; $index++) {
        $line = $frontmatter[$index]
        if ($line -match '^name:\s*(.+)$') {
            $hasName = $true
            $name = $Matches[1].Trim()
        }
        if ($line -match '^description:\s*(.*)$') {
            $hasDescription = $true
            $description = $Matches[1].Trim()
            if (
                -not [string]::IsNullOrWhiteSpace($description) -and
                $description -notmatch '^[>|]' -and
                $description -notmatch '^(["'']).*\1$'
            ) {
                $frontmatter[$index] = 'description: >-'
                $frontmatter.Insert($index + 1, "  $description")
                $index++
            }
        }
        if ($line -match '^metadata:\s*$') {
            $hasMetadata = $true
            $metadataIndex = $index
        }
        if ($line -match '^\s+short-description:\s*(.+)$') {
            $hasShortDescription = $true
        }
    }

    if (-not $hasName) {
        $frontmatter.Add("name: $(ConvertTo-YamlScalar $name)")
    }
    if (-not $hasDescription) {
        $description = $name
        $frontmatter.Add('description: >-')
        $frontmatter.Add("  $description")
    }
    $descriptionForShort = $description
    if (
        [string]::IsNullOrWhiteSpace($descriptionForShort) -or
        $descriptionForShort -match '^[>|]'
    ) {
        $descriptionForShort = $name
    }
    elseif ($descriptionForShort -match '^"([^"\\]*)"$') {
        $descriptionForShort = $Matches[1]
    }
    elseif (
        $descriptionForShort.StartsWith('"') -or
        $descriptionForShort.StartsWith("'")
    ) {
        $descriptionForShort = $name
    }
    $shortDescription = ($descriptionForShort -split '\.\s+', 2)[0].TrimEnd('.')
    if (-not $hasShortDescription) {
        if (-not $hasMetadata) {
            $frontmatter.Add('metadata:')
            $frontmatter.Add(
                "  short-description: $(ConvertTo-YamlScalar $shortDescription)"
            )
        }
        else {
            $metadataEnd = $frontmatter.Count
            for (
                $index = $metadataIndex + 1;
                $index -lt $frontmatter.Count;
                $index++
            ) {
                if ($frontmatter[$index] -match '^\S') {
                    $metadataEnd = $index
                    break
                }
            }
            $frontmatter.Insert(
                $metadataEnd,
                "  short-description: $(ConvertTo-YamlScalar $shortDescription)"
            )
        }
    }

    $result = New-Object Collections.Generic.List[string]
    $result.Add('---')
    foreach ($line in $frontmatter) {
        $result.Add($line)
    }
    $result.Add('---')
    for ($index = $closingFence + 1; $index -lt $lines.Count; $index++) {
        $result.Add($lines[$index])
    }
    return $result -join "`n"
}

function Copy-SkillSet {
    param(
        [string]$Source,
        [string]$Destination
    )

    Assert-NoReparsePoints $Source
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }

    foreach ($skillDirectory in Get-ChildItem -LiteralPath $Source -Directory) {
        if ($skillDirectory.Name.StartsWith('.')) {
            continue
        }
        if (-not (Test-SafeLeafName $skillDirectory.Name)) {
            throw "Unsafe staged skill name: $($skillDirectory.Name)"
        }
        $destinationDirectory = Get-ContainedChildPath $Destination $skillDirectory.Name
        if (Test-Path -LiteralPath $destinationDirectory) {
            Assert-NoReparsePoints $destinationDirectory
            Remove-Item -LiteralPath $destinationDirectory -Recurse -Force
        }
        Copy-File (
            Join-Path $skillDirectory.FullName 'SKILL.md'
        ) (Join-Path $destinationDirectory 'SKILL.md')
        foreach ($name in @('examples', 'references', 'scripts', 'agents')) {
            Copy-DirectoryOverlay (
                Join-Path $skillDirectory.FullName $name
            ) (Join-Path $destinationDirectory $name)
        }
        $skillFile = Join-Path $destinationDirectory 'SKILL.md'
        if (Test-Path -LiteralPath $skillFile -PathType Leaf) {
            $content = [IO.File]::ReadAllText($skillFile)
            Write-Utf8File $skillFile (
                ConvertTo-SkillDocument $content $skillDirectory.Name
            )
        }
    }
}

function Sync-ManagedSkills {
    param(
        [string]$Stage,
        [string]$Destination
    )

    $currentNames = New-Object Collections.Generic.List[string]
    if (Test-Path -LiteralPath $Stage -PathType Container) {
        $skillDirectories = Get-ChildItem -LiteralPath $Stage -Directory |
            Sort-Object Name
        foreach ($skillDirectory in $skillDirectories) {
            if (-not $skillDirectory.Name.StartsWith('.')) {
                if (-not (Test-SafeLeafName $skillDirectory.Name)) {
                    throw "Unsafe staged skill name: $($skillDirectory.Name)"
                }
                $currentNames.Add($skillDirectory.Name)
            }
        }
    }

    $manifest = Join-Path $Destination '.ai-config-managed'
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        foreach ($oldName in [IO.File]::ReadAllLines($manifest)) {
            if ([string]::IsNullOrWhiteSpace($oldName)) {
                continue
            }
            if (-not (Test-SafeLeafName $oldName)) {
                Write-Warning "Ignoring unsafe managed skill name: $oldName"
                continue
            }
            try {
                $orphan = Get-ContainedChildPath $Destination $oldName
            }
            catch {
                Write-Warning "Ignoring unsafe managed skill name: $oldName"
                continue
            }
            if (-not $currentNames.Contains($oldName) -and (Test-Path -LiteralPath $orphan)) {
                Assert-NoReparsePoints $orphan
                Remove-Item -LiteralPath $orphan -Recurse -Force
            }
        }
    }

    foreach ($name in $currentNames) {
        $stageSkill = Get-ContainedChildPath $Stage $name
        $destinationSkill = Get-ContainedChildPath $Destination $name
        Sync-DirectoryMirror (
            $stageSkill
        ) $destinationSkill
    }

    if (
        $currentNames.Count -gt 0 -or
        (Test-Path -LiteralPath $Destination -PathType Container)
    ) {
        if ($currentNames.Count -gt 0) {
            $content = ($currentNames -join "`n") + "`n"
        }
        else {
            $content = ''
        }
        Write-Utf8File $manifest $content
    }
}

function Get-HashHex {
    param([byte[]]$Bytes)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($Bytes)
    }
    finally {
        $sha256.Dispose()
    }
    return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
}

function Get-FileFingerprint {
    param([string]$Path)

    Assert-NoReparsePoints $Path
    $stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($stream)
    }
    finally {
        $sha256.Dispose()
        $stream.Dispose()
    }
    return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
}

function Get-DirectoryFingerprint {
    param([string]$Path)

    Assert-NoReparsePoints $Path
    $root = (Get-Item -LiteralPath $Path -Force).FullName.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $records = New-Object Collections.Generic.List[string]
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse -Force) {
        if (Test-ExcludedLeafName $file.Name) {
            continue
        }
        $relativePath = $file.FullName.Substring($root.Length).TrimStart(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        ).Replace([IO.Path]::DirectorySeparatorChar, '/')
        $records.Add($relativePath + [char]0 + (Get-FileFingerprint $file.FullName))
    }
    $ordered = [string[]]$records.ToArray()
    if ($env:OS -eq 'Windows_NT') {
        $comparer = [StringComparer]::OrdinalIgnoreCase
    }
    else {
        $comparer = [StringComparer]::Ordinal
    }
    [Array]::Sort($ordered, $comparer)
    $content = $ordered -join "`n"
    return Get-HashHex ([Text.Encoding]::UTF8.GetBytes($content))
}

function Get-PathFingerprint {
    param(
        [string]$Path,
        [string]$Kind
    )

    if ($Kind -eq 'file') {
        return Get-FileFingerprint $Path
    }
    if ($Kind -eq 'directory') {
        return Get-DirectoryFingerprint $Path
    }
    throw "Cannot fingerprint path kind: $Kind"
}

function Test-PathIdentity {
    param(
        [string]$Left,
        [string]$Right
    )

    $leftFull = [IO.Path]::GetFullPath($Left)
    $rightFull = [IO.Path]::GetFullPath($Right)
    return [string]::Equals($leftFull, $rightFull, (Get-PathComparison))
}

function Read-OwnershipState {
    param([string]$Path)

    $entries = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $entries
    }
    if (Test-IsReparsePoint $Path) {
        Write-Warning "Ignoring reparse point ownership state: $Path"
        return $entries
    }
    try {
        $document = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        if ([int]$document.version -ne 1) {
            Write-Warning "Ignoring unsupported ownership state: $Path"
            return $entries
        }
        foreach ($entry in @($document.entries)) {
            if (
                $null -eq $entry -or
                [int]$entry.version -ne 1 -or
                -not (Test-SafeLeafName ([string]$entry.path)) -or
                [string]::IsNullOrWhiteSpace([string]$entry.source) -or
                @('file', 'directory', 'junction') -notcontains [string]$entry.kind
            ) {
                continue
            }
            $entries[[string]$entry.path] = $entry
        }
    }
    catch {
        Write-Warning "Ignoring unreadable ownership state: $Path"
        return @{}
    }
    return $entries
}

function Assert-RecordedFallbackDestinationsSafe {
    param(
        [hashtable]$State,
        [string]$CanonicalRoot,
        [string]$DestinationRoot
    )

    foreach ($relativePath in $State.Keys) {
        $record = $State[$relativePath]
        $source = Join-Path $CanonicalRoot $relativePath
        $destination = Join-Path $DestinationRoot $relativePath
        $destinationItem = Get-PathItem $destination
        $isReparse = Test-IsReparsePoint $destination
        if ([string]$record.kind -eq 'junction') {
            if ($null -eq $destinationItem -or -not $isReparse) {
                throw "Recorded junction destination mismatch: $destination"
            }
            Assert-ReparseTarget $destination $source
        }
        elseif ($isReparse) {
            throw "Reparse point ownership mismatch: $destination"
        }
    }
}

function Assert-CodexFallbackDestinationsSafe {
    param([string]$HomeDirectory)

    $canonical = Join-Path $HomeDirectory '.codex'
    foreach ($alternateName in @('.codex-csl', '.codex-set')) {
        $alternate = Join-Path $HomeDirectory $alternateName
        $alternateItem = Get-PathItem $alternate
        if ($null -eq $alternateItem) {
            continue
        }
        if (Test-IsReparsePoint $alternate) {
            throw "Refusing reparse point alternate Codex root: $alternate"
        }
        if (-not $alternateItem.PSIsContainer) {
            continue
        }
        $statePath = Join-Path $alternate '.ai-config-shared-state.json'
        $marker = Join-Path $alternate '.ai-config-shared-paths'
        Assert-SafeWriteTarget $statePath
        Assert-SafeWriteTarget $marker
        $state = Read-OwnershipState $statePath
        Assert-RecordedFallbackDestinationsSafe $state $canonical $alternate
    }
}

function Assert-AgyFallbackDestinationSafe {
    param([string]$HomeDirectory)

    $cliRoot = Join-Path $HomeDirectory '.gemini/antigravity-cli'
    $cliRootItem = Get-PathItem $cliRoot
    if ($null -eq $cliRootItem) {
        return
    }
    if (Test-IsReparsePoint $cliRoot) {
        throw "Refusing reparse point Antigravity CLI root: $cliRoot"
    }
    if (-not $cliRootItem.PSIsContainer) {
        return
    }
    $statePath = Join-Path $cliRoot '.ai-config-skills-state.json'
    $marker = Join-Path $cliRoot '.ai-config-skills-mirror'
    Assert-SafeWriteTarget $statePath
    Assert-SafeWriteTarget $marker
    $state = Read-OwnershipState $statePath
    $canonicalRoot = Join-Path $HomeDirectory '.gemini/antigravity'
    Assert-RecordedFallbackDestinationsSafe $state $canonicalRoot $cliRoot
}

function Write-OwnershipState {
    param(
        [string]$Path,
        [object[]]$Entries
    )

    $document = [ordered]@{
        version = 1
        entries = @($Entries)
    }
    $content = ($document | ConvertTo-Json -Depth 6) + "`n"
    New-Directory (Split-Path -Parent $Path)
    $temporary = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    $replacementBackup = ''
    try {
        Write-Utf8File $temporary $content
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            Assert-SafeWriteTarget $Path
            $replacementBackup = $Path + '.old-' + [Guid]::NewGuid().ToString('N')
            [IO.File]::Replace($temporary, $Path, $replacementBackup)
        }
        else {
            [IO.File]::Move($temporary, $Path)
        }
        $temporary = ''
    }
    finally {
        if (
            -not [string]::IsNullOrWhiteSpace($temporary) -and
            (Test-Path -LiteralPath $temporary)
        ) {
            Remove-Item -LiteralPath $temporary -Force
        }
        if (
            -not [string]::IsNullOrWhiteSpace($replacementBackup) -and
            (Test-Path -LiteralPath $replacementBackup)
        ) {
            Remove-Item -LiteralPath $replacementBackup -Force
        }
    }
}

function New-OwnershipEntry {
    param(
        [string]$RelativePath,
        [string]$Source,
        [string]$Destination,
        [string]$Kind
    )

    $entry = [ordered]@{
        version = 1
        path = $RelativePath
        source = [IO.Path]::GetFullPath($Source)
        kind = $Kind
    }
    if ($Kind -eq 'junction') {
        $entry.target = [IO.Path]::GetFullPath($Source)
    }
    else {
        $entry.fingerprint = Get-PathFingerprint $Destination $Kind
    }
    return [pscustomobject]$entry
}

function Test-OwnershipRecord {
    param(
        [object]$Record,
        [string]$Source,
        [string]$Destination
    )

    if ($null -eq $Record) {
        return $false
    }
    if (-not (Test-PathIdentity ([string]$Record.source) $Source)) {
        Write-Warning "Fallback ownership/content changed: $Destination"
        return $false
    }
    $item = Get-PathItem $Destination
    if ($null -eq $item) {
        Write-Warning "Fallback ownership/content changed: $Destination"
        return $false
    }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        if ([string]$Record.kind -ne 'junction') {
            throw "Reparse point ownership mismatch: $Destination"
        }
        Assert-ReparseTarget $Destination $Source
        return $true
    }
    if ([string]$Record.kind -eq 'junction') {
        Write-Warning "Fallback ownership/content changed: $Destination"
        return $false
    }
    if ($item.PSIsContainer) {
        $kind = 'directory'
    }
    else {
        $kind = 'file'
    }
    if ($kind -ne [string]$Record.kind) {
        Write-Warning "Fallback ownership/content changed: $Destination"
        return $false
    }
    $fingerprint = Get-PathFingerprint $Destination $kind
    if ($fingerprint -ne [string]$Record.fingerprint) {
        Write-Warning "Fallback ownership/content changed: $Destination"
        return $false
    }
    return $true
}

function Remove-MarkerManagedPath {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    Assert-NoReparsePoints $Path
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) {
        Remove-Item -LiteralPath $Path -Force
        return
    }
    Remove-Item -LiteralPath $Path -Recurse -Force
}

function Sync-CodexAlternateHomes {
    param([string]$HomeDirectory)

    $canonical = Join-Path $HomeDirectory '.codex'
    $managedPaths = @(
        'AGENTS.md', 'config.toml', 'rules', 'skills', 'plugins', 'prompts'
    )
    foreach ($alternateName in @('.codex-csl', '.codex-set')) {
        $alternate = Join-Path $HomeDirectory $alternateName
        if (Test-IsReparsePoint $alternate) {
            throw "Refusing reparse point alternate Codex root: $alternate"
        }
        if (-not (Test-Path -LiteralPath $alternate -PathType Container)) {
            continue
        }

        $marker = Join-Path $alternate '.ai-config-shared-paths'
        $statePath = Join-Path $alternate '.ai-config-shared-state.json'
        $state = Read-OwnershipState $statePath
        $newEntries = New-Object Collections.Generic.List[object]

        foreach ($relativePath in $managedPaths) {
            $source = Join-Path $canonical $relativePath
            $destination = Join-Path $alternate $relativePath
            $sourceItem = Get-PathItem $source
            $destinationItem = Get-PathItem $destination
            if ($state.ContainsKey($relativePath)) {
                $record = $state[$relativePath]
            }
            else {
                $record = $null
            }

            if ($null -ne $destinationItem -and $null -eq $record) {
                Write-Warning "Not replacing unmanaged alternate Codex path: $destination"
                continue
            }
            if ($null -eq $destinationItem -and $null -ne $record) {
                Write-Warning "Fallback ownership/content changed: $destination"
                $newEntries.Add($record)
                continue
            }
            if ($null -ne $destinationItem) {
                if (-not (Test-OwnershipRecord $record $source $destination)) {
                    if ($null -ne $record) {
                        $newEntries.Add($record)
                    }
                    continue
                }
            }

            if ($null -eq $sourceItem) {
                if ($null -ne $destinationItem) {
                    if (Test-IsReparsePoint $destination) {
                        Assert-ReparseTarget $destination $source
                        Remove-Item -LiteralPath $destination -Force
                    }
                    else {
                        Remove-MarkerManagedPath $destination
                    }
                }
                continue
            }

            if ($null -ne $destinationItem) {
                if ([string]$record.kind -eq 'junction') {
                    $newEntries.Add(
                        (New-OwnershipEntry $relativePath $source $destination 'junction')
                    )
                    continue
                }
                if ($sourceItem.PSIsContainer -ne $destinationItem.PSIsContainer) {
                    Remove-MarkerManagedPath $destination
                    $destinationItem = $null
                }
            }

            if (
                $null -eq $destinationItem -and
                $sourceItem.PSIsContainer -and
                $env:OS -eq 'Windows_NT'
            ) {
                try {
                    New-Directory (Split-Path -Parent $destination)
                    $junctionParameters = @{
                        ItemType = 'Junction'
                        Path = $destination
                        Target = $source
                        ErrorAction = 'Stop'
                    }
                    $null = New-Item @junctionParameters
                    $newEntries.Add(
                        (New-OwnershipEntry $relativePath $source $destination 'junction')
                    )
                    continue
                }
                catch {
                    Write-Warning "Could not create junction for $destination; using copy fallback"
                }
            }

            if ($sourceItem.PSIsContainer) {
                Sync-DirectoryMirror $source $destination
                $kind = 'directory'
            }
            else {
                Copy-File $source $destination
                $kind = 'file'
            }
            $newEntries.Add(
                (New-OwnershipEntry $relativePath $source $destination $kind)
            )
        }

        Write-OwnershipState $statePath $newEntries.ToArray()
        $managedNames = New-Object Collections.Generic.List[string]
        foreach ($entry in $newEntries) {
            $managedNames.Add([string]$entry.path)
        }
        $content = ''
        if ($managedNames.Count -gt 0) {
            $content = ($managedNames -join "`n") + "`n"
        }
        Write-Utf8File $marker $content
    }
}

function Sync-AgySkillsSurface {
    param([string]$HomeDirectory)

    $canonical = Join-Path $HomeDirectory '.gemini/antigravity/skills'
    if (-not (Test-Path -LiteralPath $canonical -PathType Container)) {
        return
    }

    $cliRoot = Join-Path $HomeDirectory '.gemini/antigravity-cli'
    $cliSkills = Join-Path $cliRoot 'skills'
    $marker = Join-Path $cliRoot '.ai-config-skills-mirror'
    $statePath = Join-Path $cliRoot '.ai-config-skills-state.json'
    $state = Read-OwnershipState $statePath
    if ($state.ContainsKey('skills')) {
        $record = $state['skills']
    }
    else {
        $record = $null
    }
    $destinationItem = Get-PathItem $cliSkills

    if ($null -ne $destinationItem) {
        if ($null -eq $record) {
            Write-Warning "Not replacing unmanaged Antigravity skills path: $cliSkills"
            return
        }
        if (-not (Test-OwnershipRecord $record $canonical $cliSkills)) {
            Write-OwnershipState $statePath @($record)
            return
        }
    }
    elseif ($null -ne $record) {
        Write-Warning "Fallback ownership/content changed: $cliSkills"
        Write-OwnershipState $statePath @($record)
        return
    }

    if ($null -ne $destinationItem -and [string]$record.kind -eq 'junction') {
        $entry = New-OwnershipEntry 'skills' $canonical $cliSkills 'junction'
        Write-OwnershipState $statePath @($entry)
        Write-Utf8File $marker "skills`n"
        return
    }

    if ($null -eq $destinationItem -and $env:OS -eq 'Windows_NT') {
        try {
            New-Directory $cliRoot
            $junctionParameters = @{
                ItemType = 'Junction'
                Path = $cliSkills
                Target = $canonical
                ErrorAction = 'Stop'
            }
            $null = New-Item @junctionParameters
            $entry = New-OwnershipEntry 'skills' $canonical $cliSkills 'junction'
            Write-OwnershipState $statePath @($entry)
            Write-Utf8File $marker "skills`n"
            return
        }
        catch {
            Write-Warning "Could not create Antigravity skills junction; using copy fallback"
        }
    }

    Sync-DirectoryMirror $canonical $cliSkills
    $entry = New-OwnershipEntry 'skills' $canonical $cliSkills 'directory'
    Write-OwnershipState $statePath @($entry)
    Write-Utf8File $marker "skills`n"
}

function Project-AgentsToSkills {
    param(
        [string]$AgentsDirectory,
        [string]$SkillsDirectory
    )

    Assert-NoReparsePoints $AgentsDirectory
    if (-not (Test-Path -LiteralPath $AgentsDirectory -PathType Container)) {
        return
    }

    foreach ($agentFile in Get-ChildItem -LiteralPath $AgentsDirectory -File -Filter '*.md') {
        $skillDirectory = Join-Path $SkillsDirectory $agentFile.BaseName
        $skillFile = Join-Path $skillDirectory 'SKILL.md'
        $content = [IO.File]::ReadAllText($agentFile.FullName)
        Write-Utf8File $skillFile (
            ConvertTo-SkillDocument $content $agentFile.BaseName
        )
    }
}

function Assert-ProjectionSourcesSafe {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        Assert-NoReparsePoints $path
    }
}

function Stage-ClaudeProjection {
    param([string]$Destination)

    $source = Join-Path $PSScriptRoot 'claude'
    $managedSources = New-Object Collections.Generic.List[string]
    foreach ($name in @(
        'CLAUDE.md', 'mcp.json', 'settings.json', 'statusline.sh',
        'rules', 'agents', 'commands'
    )) {
        $managedSources.Add((Join-Path $source $name))
    }
    Assert-ProjectionSourcesSafe $managedSources.ToArray()
    foreach ($name in @('CLAUDE.md', 'mcp.json', 'settings.json', 'statusline.sh')) {
        Copy-File (Join-Path $source $name) (Join-Path $Destination $name)
    }
    foreach ($name in @('rules', 'agents', 'commands')) {
        Copy-DirectoryOverlay (
            Join-Path $source $name
        ) (Join-Path $Destination $name)
    }
}

function Stage-CodexProjection {
    param(
        [string]$Destination,
        [string]$ClaudeSource = '',
        [string]$SharedRoot = '',
        [bool]$PreferClaudeInstructions = $false
    )

    if ([string]::IsNullOrWhiteSpace($ClaudeSource)) {
        $ClaudeSource = Join-Path $PSScriptRoot 'claude'
    }
    if ([string]::IsNullOrWhiteSpace($SharedRoot)) {
        $SharedRoot = Join-Path $PSScriptRoot 'claude/shared'
    }
    $codexSource = Join-Path $PSScriptRoot 'codex'
    if ($PreferClaudeInstructions) {
        $instructionSource = Join-Path $ClaudeSource 'CLAUDE.md'
    }
    else {
        $instructionSource = Join-Path $codexSource 'AGENTS.md'
        Assert-NoReparsePoints $instructionSource
        if (-not (Test-Path -LiteralPath $instructionSource -PathType Leaf)) {
            $instructionSource = Join-Path $ClaudeSource 'CLAUDE.md'
        }
    }
    Assert-ProjectionSourcesSafe @(
        $instructionSource,
        (Join-Path $codexSource 'config.toml'),
        (Join-Path $ClaudeSource 'rules'),
        (Join-Path $codexSource 'rules'),
        (Join-Path $ClaudeSource 'agents'),
        (Join-Path $codexSource 'skills'),
        (Join-Path $ClaudeSource 'skills'),
        (Join-Path $SharedRoot 'both'),
        (Join-Path $SharedRoot 'codex')
    )
    Copy-File $instructionSource (Join-Path $Destination 'AGENTS.md')
    Copy-File (
        Join-Path $codexSource 'config.toml'
    ) (Join-Path $Destination 'config.toml')
    Copy-DirectoryOverlay (
        Join-Path $ClaudeSource 'rules'
    ) (Join-Path $Destination 'rules')
    Copy-DirectoryOverlay (
        Join-Path $codexSource 'rules'
    ) (Join-Path $Destination 'rules')
    Project-AgentsToSkills (
        Join-Path $ClaudeSource 'agents'
    ) (Join-Path $Destination 'skills')
    Copy-SkillSet (
        Join-Path $codexSource 'skills'
    ) (Join-Path $Destination 'skills')
    Copy-SkillSet (
        Join-Path $ClaudeSource 'skills'
    ) (Join-Path $Destination 'skills')
    Copy-SkillSet (
        Join-Path $SharedRoot 'both'
    ) (Join-Path $Destination 'skills')
    Copy-SkillSet (
        Join-Path $SharedRoot 'codex'
    ) (Join-Path $Destination 'skills')
}

function Stage-AgyProjection {
    param(
        [string]$Destination,
        [string]$ClaudeSource = '',
        [string]$SharedRoot = '',
        [bool]$PreferClaudeMcp = $false
    )

    if ([string]::IsNullOrWhiteSpace($ClaudeSource)) {
        $ClaudeSource = Join-Path $PSScriptRoot 'claude'
    }
    if ([string]::IsNullOrWhiteSpace($SharedRoot)) {
        $SharedRoot = Join-Path $PSScriptRoot 'claude/shared'
    }
    $agySource = Join-Path $PSScriptRoot 'agy'
    if ($PreferClaudeMcp) {
        $mcpSource = Join-Path $ClaudeSource 'mcp.json'
    }
    else {
        $mcpSource = Join-Path $agySource 'mcp_config.json'
        Assert-NoReparsePoints $mcpSource
        if (-not (Test-Path -LiteralPath $mcpSource -PathType Leaf)) {
            $mcpSource = Join-Path $ClaudeSource 'mcp.json'
        }
    }
    Assert-ProjectionSourcesSafe @(
        $mcpSource,
        (Join-Path $agySource 'settings.json'),
        (Join-Path $ClaudeSource 'agents'),
        (Join-Path $agySource 'skills'),
        (Join-Path $ClaudeSource 'skills'),
        (Join-Path $SharedRoot 'both'),
        (Join-Path $SharedRoot 'agy'),
        (Join-Path $ClaudeSource 'plugins')
    )
    Copy-File $mcpSource (Join-Path $Destination 'mcp_config.json')
    Copy-File (
        Join-Path $agySource 'settings.json'
    ) (Join-Path $Destination 'settings.json')
    Project-AgentsToSkills (
        Join-Path $ClaudeSource 'agents'
    ) (Join-Path $Destination 'skills')
    Copy-SkillSet (
        Join-Path $agySource 'skills'
    ) (Join-Path $Destination 'skills')
    Copy-SkillSet (
        Join-Path $ClaudeSource 'skills'
    ) (Join-Path $Destination 'skills')
    Copy-SkillSet (
        Join-Path $SharedRoot 'both'
    ) (Join-Path $Destination 'skills')
    Copy-SkillSet (
        Join-Path $SharedRoot 'agy'
    ) (Join-Path $Destination 'skills')
    Copy-DirectoryOverlay (
        Join-Path $ClaudeSource 'plugins'
    ) (Join-Path $Destination 'plugins')
}

function Stage-RepoProjection {
    param(
        [string]$Tool,
        [string]$Destination
    )

    switch ($Tool) {
        'claude' { Stage-ClaudeProjection $Destination }
        'codex' { Stage-CodexProjection $Destination }
        'agy' { Stage-AgyProjection $Destination }
        default { throw "Unknown tool: $Tool" }
    }
}

function Get-CodexProjectsBlock {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }

    $projects = New-Object Collections.Generic.List[string]
    $inProjects = $false
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\[projects\.') {
            $inProjects = $true
            $projects.Add($line)
            continue
        }
        if ($line -match '^\[') {
            $inProjects = $false
            continue
        }
        if ($inProjects) {
            $projects.Add($line)
        }
    }
    return ($projects -join "`n").TrimEnd()
}

function Get-CodexGeneralConfigContent {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }
    Assert-NoReparsePoints $Path
    $general = New-Object Collections.Generic.List[string]
    $inProjects = $false
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\[projects\.') {
            $inProjects = $true
            continue
        }
        if ($line -match '^\[') {
            $inProjects = $false
        }
        if (-not $inProjects) {
            $general.Add($line)
        }
    }
    $content = ($general -join "`n").TrimEnd([char[]]"`r`n")
    if ([string]::IsNullOrEmpty($content)) {
        return ''
    }
    return $content + "`n"
}

function Remove-EmptyManagedDirectory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }
    $child = Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1
    if ($null -eq $child) {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Invoke-InitClaude {
    param([string]$HomeDirectory)

    $source = Join-Path $HomeDirectory '.claude'
    if (Test-IsReparsePoint $source) {
        throw "Refusing reparse point Claude config directory: $source"
    }
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Claude config directory not found: $source"
    }
    foreach ($name in @('CLAUDE.md', 'mcp.json', 'settings.json', 'statusline.sh')) {
        Assert-NoReparsePoints (Join-Path $source $name)
    }
    foreach ($name in @('rules', 'agents', 'commands')) {
        Assert-NoReparsePoints (Join-Path $source $name)
    }
    $destination = Join-Path $PSScriptRoot 'claude'
    foreach ($name in @('CLAUDE.md', 'mcp.json', 'settings.json', 'statusline.sh')) {
        $sourcePath = Join-Path $source $name
        $destinationPath = Join-Path $destination $name
        if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
            Copy-File $sourcePath $destinationPath
        }
        elseif ($null -ne (Get-PathItem $destinationPath)) {
            Remove-MarkerManagedPath $destinationPath
        }
    }
    foreach ($name in @('rules', 'agents', 'commands')) {
        $sourcePath = Join-Path $source $name
        $destinationPath = Join-Path $destination $name
        Sync-DirectoryMirror $sourcePath $destinationPath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
            Remove-EmptyManagedDirectory $destinationPath
        }
    }
    Write-Output 'Initialized: claude'
}

function Invoke-InitCodex {
    param([string]$HomeDirectory)

    $source = Join-Path $HomeDirectory '.codex'
    if (Test-IsReparsePoint $source) {
        throw "Refusing reparse point Codex config directory: $source"
    }
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Codex config directory not found: $source"
    }
    $sourceConfig = Join-Path $source 'config.toml'
    Assert-NoReparsePoints $sourceConfig
    if (Test-Path -LiteralPath $sourceConfig -PathType Leaf) {
        $destination = Join-Path $PSScriptRoot 'codex/config.toml'
        Write-Utf8File $destination (Get-CodexGeneralConfigContent $sourceConfig)
    }
    Write-Output 'Initialized: codex'
}

function Invoke-InitAgy {
    param([string]$HomeDirectory)

    $source = Join-Path $HomeDirectory '.gemini/antigravity-cli'
    if (Test-IsReparsePoint $source) {
        throw "Refusing reparse point Antigravity CLI directory: $source"
    }
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        Write-Warning "Antigravity CLI directory not found: $source"
        return
    }
    $sourceSettings = Join-Path $source 'settings.json'
    Assert-NoReparsePoints $sourceSettings
    if (Test-Path -LiteralPath $sourceSettings -PathType Leaf) {
        Copy-File $sourceSettings (Join-Path $PSScriptRoot 'agy/settings.json')
    }
    Write-Output 'Initialized: agy'
}

function Invoke-Init {
    param([string]$Tool)

    $homeDirectory = Get-UserHome
    if ([string]::IsNullOrWhiteSpace($homeDirectory)) {
        throw 'Unable to resolve the user home directory'
    }
    $tools = @(Get-SelectedTools $Tool @('claude', 'codex', 'agy'))
    foreach ($currentTool in $tools) {
        switch ($currentTool) {
            'claude' { Invoke-InitClaude $homeDirectory }
            'codex' { Invoke-InitCodex $homeDirectory }
            'agy' { Invoke-InitAgy $homeDirectory }
        }
    }
}

function Test-FileBytesEqual {
    param(
        [string]$Left,
        [string]$Right
    )

    Assert-NoReparsePoints $Left
    Assert-NoReparsePoints $Right
    $leftBytes = [IO.File]::ReadAllBytes($Left)
    $rightBytes = [IO.File]::ReadAllBytes($Right)
    if ($leftBytes.Length -ne $rightBytes.Length) {
        return $false
    }
    for ($index = 0; $index -lt $leftBytes.Length; $index++) {
        if ($leftBytes[$index] -ne $rightBytes[$index]) {
            return $false
        }
    }
    return $true
}

function ConvertFrom-MirrorScalar {
    param([string]$Value)

    $trimmed = $Value.Trim()
    if (
        $trimmed.Length -ge 2 -and
        $trimmed.StartsWith("'") -and
        $trimmed.EndsWith("'")
    ) {
        return $trimmed.Substring(1, $trimmed.Length - 2).Replace("''", "'")
    }
    if (
        $trimmed.Length -ge 2 -and
        $trimmed.StartsWith('"') -and
        $trimmed.EndsWith('"')
    ) {
        try {
            return [string]($trimmed | ConvertFrom-Json)
        }
        catch {
            return $trimmed.Substring(1, $trimmed.Length - 2)
        }
    }
    return $trimmed
}

function Get-SkillMirrorMetadata {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    Assert-NoReparsePoints $Path
    $lines = [IO.File]::ReadAllLines($Path)
    if ($lines.Length -eq 0 -or $lines[0].Trim() -ne '---') {
        return $null
    }
    $inMetadata = $false
    $mirrorOf = ''
    $mirrorHash = ''
    for ($index = 1; $index -lt $lines.Length; $index++) {
        $line = $lines[$index]
        if ($line.Trim() -eq '---') {
            break
        }
        if ($line -match '^metadata\s*:\s*$') {
            $inMetadata = $true
            continue
        }
        if ($line -match '^\S') {
            $inMetadata = $false
        }
        if (-not $inMetadata) {
            continue
        }
        if ($line -match '^\s+mirror-of\s*:\s*(.*?)\s*$') {
            $mirrorOf = ConvertFrom-MirrorScalar $Matches[1]
        }
        elseif ($line -match '^\s+mirror-hash\s*:\s*(.*?)\s*$') {
            $mirrorHash = ConvertFrom-MirrorScalar $Matches[1]
        }
    }
    if ([string]::IsNullOrWhiteSpace($mirrorOf)) {
        return $null
    }
    return [pscustomobject]@{
        source = $mirrorOf
        hash = $mirrorHash
    }
}

function Resolve-MirrorSourcePath {
    param(
        [string]$Path,
        [string]$HomeDirectory
    )

    if ($Path -eq '~') {
        return [IO.Path]::GetFullPath($HomeDirectory)
    }
    if ($Path.StartsWith('~/') -or $Path.StartsWith('~\')) {
        return [IO.Path]::GetFullPath((Join-Path $HomeDirectory $Path.Substring(2)))
    }
    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $Path))
}

function Show-SharedMirrorDrift {
    param([string]$HomeDirectory)

    $sharedRoot = Join-Path $PSScriptRoot 'claude/shared'
    $checked = 0
    $stale = 0
    foreach ($scope in @('both', 'codex', 'agy')) {
        $scopeRoot = Join-Path $sharedRoot $scope
        if (-not (Test-Path -LiteralPath $scopeRoot -PathType Container)) {
            continue
        }
        foreach ($skill in Get-ChildItem -LiteralPath $scopeRoot -Directory -Force) {
            if (($skill.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing reparse point shared skill: $($skill.FullName)"
            }
            $skillFile = Join-Path $skill.FullName 'SKILL.md'
            $metadata = Get-SkillMirrorMetadata $skillFile
            if ($null -eq $metadata) {
                continue
            }
            $checked++
            $relativePath = "$scope/$($skill.Name)/SKILL.md"
            $sourcePath = Resolve-MirrorSourcePath (
                [string]$metadata.source
            ) $HomeDirectory
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                Write-Warning "mirror source missing: $relativePath"
                $stale++
                continue
            }
            $currentHash = Get-FileFingerprint $sourcePath
            if (-not [string]::Equals(
                $currentHash,
                ([string]$metadata.hash).ToLowerInvariant(),
                [StringComparison]::Ordinal
            )) {
                Write-Warning "mirror stale: $relativePath"
                Write-Output "  new SHA256: $currentHash"
                $stale++
            }
        }
    }
    if ($checked -gt 0 -and $stale -eq 0) {
        Write-Output "All $checked mirrored shared skills up to date"
    }
}

function Invoke-Status {
    param([string]$Tool)

    $homeDirectory = Get-UserHome
    if ([string]::IsNullOrWhiteSpace($homeDirectory)) {
        throw 'Unable to resolve the user home directory'
    }
    $tools = @(Get-SelectedTools $Tool @('claude', 'codex', 'agy'))
    $stageRoot = Join-Path (
        [IO.Path]::GetTempPath()
    ) ('ai-config-status-' + [Guid]::NewGuid().ToString('N'))
    New-Directory $stageRoot
    try {
        foreach ($currentTool in $tools) {
            $stage = Join-Path $stageRoot $currentTool
            Stage-RepoProjection $currentTool $stage
            Write-Output "Status: $currentTool"
            if (-not (Test-DirectoryHasFiles $stage)) {
                Write-Warning "No config in ai-config/$currentTool/"
                continue
            }
            $liveDirectory = Get-ToolLiveDirectory $currentTool $homeDirectory
            if (-not (Test-Path -LiteralPath $liveDirectory -PathType Container)) {
                Write-Warning "Tool home directory not found: $liveDirectory"
                continue
            }
            $stageFull = (Get-Item -LiteralPath $stage).FullName.TrimEnd(
                [IO.Path]::DirectorySeparatorChar,
                [IO.Path]::AltDirectorySeparatorChar
            )
            $hasDifferences = $false
            $files = Get-ChildItem -LiteralPath $stageFull -File -Recurse -Force |
                Sort-Object FullName
            foreach ($file in $files) {
                if (Test-ExcludedLeafName $file.Name) {
                    continue
                }
                $relativePath = $file.FullName.Substring($stageFull.Length).TrimStart(
                    [IO.Path]::DirectorySeparatorChar,
                    [IO.Path]::AltDirectorySeparatorChar
                )
                $displayPath = $relativePath.Replace('\', '/')
                $livePath = Join-Path $liveDirectory $relativePath
                if (-not (Test-Path -LiteralPath $livePath -PathType Leaf)) {
                    Write-Output "  + $displayPath (only in ai-config)"
                    $hasDifferences = $true
                    continue
                }
                if ($currentTool -eq 'codex' -and $displayPath -eq 'config.toml') {
                    $stageContent = [IO.File]::ReadAllText($file.FullName)
                    $liveContent = Get-CodexGeneralConfigContent $livePath
                    $filesMatch = [string]::Equals(
                        $stageContent,
                        $liveContent,
                        [StringComparison]::Ordinal
                    )
                }
                else {
                    $filesMatch = Test-FileBytesEqual $file.FullName $livePath
                }
                if (-not $filesMatch) {
                    Write-Output "  ~ $displayPath"
                    $hasDifferences = $true
                }
            }
            if (-not $hasDifferences) {
                Write-Output 'No differences found'
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $stageRoot) {
            Assert-NoReparsePoints $stageRoot
            Remove-Item -LiteralPath $stageRoot -Recurse -Force
        }
    }
    Show-SharedMirrorDrift $homeDirectory
}

function Get-NonHiddenFileCount {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return 0
    }
    $rootFull = (Get-Item -LiteralPath $Root -Force).FullName.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $count = 0
    foreach ($file in Get-ChildItem -LiteralPath $rootFull -File -Recurse -Force) {
        $relativePath = $file.FullName.Substring($rootFull.Length).TrimStart(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        )
        $hidden = $false
        foreach ($segment in ($relativePath -split '[/\\]')) {
            if ($segment.StartsWith('.')) {
                $hidden = $true
                break
            }
        }
        if (-not $hidden) {
            $count++
        }
    }
    return $count
}

function Invoke-List {
    foreach ($tool in @('claude', 'codex', 'agy')) {
        $count = Get-NonHiddenFileCount (Join-Path $PSScriptRoot $tool)
        Write-Output "$tool ($count files)"
    }
    $backupRoot = Join-Path (Get-UserHome) '.ai-config-backup'
    if (Test-IsReparsePoint $backupRoot) {
        Write-Warning "Ignoring reparse point backup root: $backupRoot"
        $backupCount = 0
    }
    else {
        $backupCount = @(Get-CompletedBackupSnapshots $backupRoot).Count
    }
    Write-Output "Backups: $backupCount completed snapshots"
}

function Apply-ClaudeProjection {
    param(
        [string]$Stage,
        [string]$HomeDirectory
    )

    $destination = Join-Path $HomeDirectory '.claude'
    foreach ($name in @('CLAUDE.md', 'mcp.json', 'settings.json', 'statusline.sh')) {
        Copy-File (Join-Path $Stage $name) (Join-Path $destination $name)
    }
    foreach ($name in @('rules', 'agents', 'commands')) {
        Sync-DirectoryMirror (
            Join-Path $Stage $name
        ) (Join-Path $destination $name)
    }
}

function Apply-CodexProjection {
    param(
        [string]$Stage,
        [string]$HomeDirectory
    )

    $destination = Join-Path $HomeDirectory '.codex'
    Copy-File (
        Join-Path $Stage 'AGENTS.md'
    ) (Join-Path $destination 'AGENTS.md')
    Copy-DirectoryOverlay (
        Join-Path $Stage 'rules'
    ) (Join-Path $destination 'rules')
    Sync-ManagedSkills (
        Join-Path $Stage 'skills'
    ) (Join-Path $destination 'skills')

    $sourceConfig = Join-Path $Stage 'config.toml'
    if (Test-Path -LiteralPath $sourceConfig -PathType Leaf) {
        $destinationConfig = Join-Path $destination 'config.toml'
        $projects = Get-CodexProjectsBlock $destinationConfig
        $content = [IO.File]::ReadAllText($sourceConfig).TrimEnd(
            [char[]]"`r`n"
        )
        if (-not [string]::IsNullOrWhiteSpace($projects)) {
            $content = "$content`n`n$projects"
        }
        Write-Utf8File $destinationConfig "$content`n"
    }
    Sync-CodexAlternateHomes $HomeDirectory
}

function Apply-AgyProjection {
    param(
        [string]$Stage,
        [string]$HomeDirectory
    )

    $destination = Join-Path $HomeDirectory '.gemini/antigravity-cli'
    foreach ($name in @('mcp_config.json', 'settings.json')) {
        Copy-File (Join-Path $Stage $name) (Join-Path $destination $name)
    }
    Copy-DirectoryOverlay (
        Join-Path $Stage 'plugins'
    ) (Join-Path $destination 'plugins')
    $installedPlugins = Join-Path $destination 'plugins/installed_plugins.json'
    if (Test-Path -LiteralPath $installedPlugins -PathType Leaf) {
        $sourcePlugins = Join-Path $HomeDirectory '.claude/plugins'
        $targetPlugins = Join-Path $destination 'plugins'
        $content = [IO.File]::ReadAllText($installedPlugins)
        $content = $content.Replace($sourcePlugins, $targetPlugins)
        $content = $content.Replace(
            $sourcePlugins.Replace('\', '\\'),
            $targetPlugins.Replace('\', '\\')
        )
        Write-Utf8File $installedPlugins $content
    }
    $canonicalSkills = Join-Path $HomeDirectory '.gemini/antigravity/skills'
    Sync-ManagedSkills (
        Join-Path $Stage 'skills'
    ) $canonicalSkills
    Sync-AgySkillsSurface $HomeDirectory
}

function Apply-ToolProjection {
    param(
        [string]$Tool,
        [string]$Stage,
        [string]$HomeDirectory
    )

    switch ($Tool) {
        'claude' { Apply-ClaudeProjection $Stage $HomeDirectory }
        'codex' { Apply-CodexProjection $Stage $HomeDirectory }
        'agy' { Apply-AgyProjection $Stage $HomeDirectory }
        default { throw "Unknown tool: $Tool" }
    }
}

function Invoke-Apply {
    param([string]$Tool)

    $homeDirectory = Get-UserHome
    if ([string]::IsNullOrWhiteSpace($homeDirectory)) {
        throw 'Unable to resolve the user home directory'
    }

    $tools = @(Get-SelectedTools $Tool @('claude', 'codex', 'agy'))

    $stageRoot = Join-Path (
        [IO.Path]::GetTempPath()
    ) ("ai-config-stage-" + [Guid]::NewGuid().ToString('N'))
    New-Directory $stageRoot
    try {
        foreach ($currentTool in $tools) {
            $stage = Join-Path $stageRoot $currentTool
            Stage-RepoProjection $currentTool $stage
            if (-not (Test-DirectoryHasFiles $stage)) {
                throw "No files staged for $currentTool"
            }
        }
        Assert-ToolDestinationsSafe $tools $homeDirectory
        $applyLock = Enter-ApplyLock $homeDirectory
        try {
            New-BackupSnapshot $tools $homeDirectory
            foreach ($currentTool in $tools) {
                $stage = Join-Path $stageRoot $currentTool
                Apply-ToolProjection $currentTool $stage $homeDirectory
            }
            Remove-OldBackupSnapshots $homeDirectory
        }
        finally {
            if ($null -ne $applyLock) {
                $applyLock.Dispose()
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $stageRoot) {
            Remove-Item -LiteralPath $stageRoot -Recurse -Force
        }
    }

    Write-Output ("Applied: " + ($tools -join ', '))
}

function Assert-ClaudeProjectionSourceSafe {
    param([string]$Source)

    if (Test-IsReparsePoint $Source) {
        throw "Refusing reparse point Claude projection source: $Source"
    }
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Claude config directory not found: $Source"
    }
    foreach ($name in @('CLAUDE.md', 'mcp.json', 'rules', 'agents', 'skills', 'plugins')) {
        Assert-NoReparsePoints (Join-Path $Source $name)
    }
}

function Invoke-Project {
    param([string]$Tool)

    if ($Tool -eq 'claude') {
        Write-Warning 'No tools projected: claude is the source'
        return
    }
    $tools = @(Get-SelectedTools $Tool @('codex', 'agy'))
    $homeDirectory = Get-UserHome
    if ([string]::IsNullOrWhiteSpace($homeDirectory)) {
        throw 'Unable to resolve the user home directory'
    }
    $claudeSource = Join-Path $homeDirectory '.claude'
    Assert-ClaudeProjectionSourceSafe $claudeSource
    $sharedRoot = Join-Path $PSScriptRoot 'claude/shared'
    $stageRoot = Join-Path (
        [IO.Path]::GetTempPath()
    ) ('ai-config-stage-' + [Guid]::NewGuid().ToString('N'))
    New-Directory $stageRoot
    try {
        foreach ($currentTool in $tools) {
            $stage = Join-Path $stageRoot $currentTool
            switch ($currentTool) {
                'codex' {
                    Stage-CodexProjection $stage $claudeSource $sharedRoot $true
                }
                'agy' {
                    Stage-AgyProjection $stage $claudeSource $sharedRoot $true
                }
            }
            if (-not (Test-DirectoryHasFiles $stage)) {
                throw "No files staged for $currentTool"
            }
        }
        Assert-ToolDestinationsSafe $tools $homeDirectory
        $applyLock = Enter-ApplyLock $homeDirectory
        try {
            New-BackupSnapshot $tools $homeDirectory
            foreach ($currentTool in $tools) {
                $stage = Join-Path $stageRoot $currentTool
                Apply-ToolProjection $currentTool $stage $homeDirectory
            }
            Remove-OldBackupSnapshots $homeDirectory
        }
        finally {
            if ($null -ne $applyLock) {
                $applyLock.Dispose()
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $stageRoot) {
            Remove-Item -LiteralPath $stageRoot -Recurse -Force
        }
    }
    Write-Output ('Projected: ' + ($tools -join ', '))
}

function Clear-RepoConfigTree {
    param([string]$Root)

    foreach ($child in @(Get-ChildItem -LiteralPath $Root -Force)) {
        if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Remove-Item -LiteralPath $child.FullName -Force
        }
        elseif ($child.PSIsContainer) {
            Clear-RepoConfigTree $child.FullName
        }
        else {
            Remove-Item -LiteralPath $child.FullName -Force
        }
    }
}

function Invoke-Reset {
    Write-Output 'Delete managed repo configuration files? [y/N]'
    $confirmation = [Console]::ReadLine()
    if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
        Write-Output 'Cancelled'
        return
    }
    $roots = New-Object Collections.Generic.List[string]
    foreach ($tool in @('claude', 'codex', 'agy')) {
        $root = Join-Path $PSScriptRoot $tool
        if (Test-IsReparsePoint $root) {
            throw "Refusing reparse point tool repo root: $root"
        }
        $roots.Add($root)
    }
    foreach ($root in $roots) {
        New-Directory $root
        Clear-RepoConfigTree $root
    }
    Write-Output 'Reset complete'
}

function Invoke-Main {
    if ($args.Count -eq 0) {
        Show-Usage
        return
    }

    $command = [string]$args[0]
    if ($command -eq 'help' -or $command -eq '--help' -or $command -eq '-h') {
        Show-Usage
        return
    }

    $toolName = 'all'
    if ($args.Count -gt 1) {
        $toolName = [string]$args[1]
    }
    $tool = Resolve-Tool $toolName
    switch ($command) {
        'apply' { Invoke-Apply $tool }
        'init' { Invoke-Init $tool }
        'status' { Invoke-Status $tool }
        'list' { Invoke-List }
        'project' { Invoke-Project $tool }
        'reset' { Invoke-Reset }
        default { throw "Unknown command: $command" }
    }
}

try {
    Invoke-Main @args
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
