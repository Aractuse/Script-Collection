<#
.SYNOPSIS
    ACL Search TUI - Analyse des permissions NTFS avec interface Text User Interface
.DESCRIPTION
    Interface TUI native PowerShell pour analyser les permissions NTFS
    Remonte automatiquement l'arborescence depuis le chemin specifie
.NOTES
    Requires: NTFSSecurity module
    Version: 3.0 TUI
#>

# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION ET INITIALISATION
# ══════════════════════════════════════════════════════════════════════════════

$host.ui.RawUI.WindowTitle = "ACL Search TUI"
$script:LastResults = @()
$script:CurrentPath = ""

# Codes ANSI
$script:ESC = [char]27
$script:Colors = @{
    Reset       = "$ESC[0m"
    Bold        = "$ESC[1m"
    Dim         = "$ESC[2m"
    # Couleurs de base
    Cyan        = "$ESC[36m"
    BrightCyan  = "$ESC[96m"
    Green       = "$ESC[32m"
    Yellow      = "$ESC[33m"
    Orange      = "$ESC[38;5;208m"
    Red         = "$ESC[31m"
    White       = "$ESC[97m"
    Gray        = "$ESC[90m"
    Magenta     = "$ESC[35m"
    BrightWhite = "$ESC[97m"
    # Couleurs ACL
    Modify      = "$ESC[38;5;208m"  # Orange
    ReadExec    = "$ESC[32m"        # Vert
    Other       = "$ESC[90m"        # Gris
}

# Caracteres de boite arrondis
$script:Box = @{
    TopLeft     = "╭"
    TopRight    = "╮"
    BottomLeft  = "╰"
    BottomRight = "╯"
    Horizontal  = "─"
    Vertical    = "│"
    TeeRight    = "├"
    TeeLeft     = "┤"
}

# ══════════════════════════════════════════════════════════════════════════════
# FONCTIONS UTILITAIRES TUI
# ══════════════════════════════════════════════════════════════════════════════

function Get-ConsoleWidth {
    try {
        return $Host.UI.RawUI.WindowSize.Width
    }
    catch {
        return 120
    }
}

function Hide-Cursor {
    Write-Host "$ESC[?25l" -NoNewline
}

function Show-Cursor {
    Write-Host "$ESC[?25h" -NoNewline
}

function Write-Centered {
    param(
        [string]$Text,
        [switch]$NoNewline
    )
    $width = Get-ConsoleWidth
    # Calculer la longueur visible (sans codes ANSI)
    $cleanText = $Text -replace '\x1b\[[0-9;]*m', ''
    $padding = [Math]::Max(0, [Math]::Floor(($width - $cleanText.Length) / 2))
    
    if ($NoNewline) {
        Write-Host (" " * $padding) -NoNewline
        Write-Host $Text -NoNewline
    }
    else {
        Write-Host (" " * $padding) -NoNewline
        Write-Host $Text
    }
}

# Fonction pour tronquer un texte intelligemment
function Get-TruncatedText {
    param(
        [string]$Text,
        [int]$MaxLength,
        [string]$Ellipsis = "..."
    )
    
    if ($Text.Length -le $MaxLength) {
        return $Text
    }
    
    return $Ellipsis + $Text.Substring($Text.Length - ($MaxLength - $Ellipsis.Length))
}

function Draw-BoxCentered {
    param(
        [string[]]$Content,
        [string]$Title = "",
        [int]$Width = 0,
        [string]$BorderColor = $Colors.Cyan,
        [int]$MaxWidth = 80
    )
    
    $consoleWidth = Get-ConsoleWidth
    
    # Calcul largeur automatique si non specifiee
    if ($Width -eq 0) {
        $maxLen = 0
        foreach ($line in $Content) {
            $cleanLine = $line -replace '\x1b\[[0-9;]*m', ''
            if ($cleanLine.Length -gt $maxLen) { $maxLen = $cleanLine.Length }
        }
        if ($Title) { 
            $cleanTitle = $Title -replace '\x1b\[[0-9;]*m', ''
            $maxLen = [Math]::Max($maxLen, $cleanTitle.Length) 
        }
        $Width = [Math]::Min($maxLen + 4, $MaxWidth)
    }
    
    # Limiter la largeur maximale
    $Width = [Math]::Min($Width, $MaxWidth)
    $innerWidth = $Width - 2
    
    # Calcul du padding pour centrer
    $paddingLeft = [Math]::Max(0, [Math]::Floor(($consoleWidth - $Width) / 2))
    $indent = " " * $paddingLeft
    
    # Tronquer le titre si necessaire
    $displayTitle = $Title
    if ($Title.Length -gt ($innerWidth - 4)) {
        $displayTitle = Get-TruncatedText -Text $Title -MaxLength ($innerWidth - 4)
    }
    
    # Ligne superieure avec titre
    if ($displayTitle) {
        $titlePadded = " $displayTitle "
        $leftBar = [Math]::Max(1, [Math]::Floor(($innerWidth - $titlePadded.Length) / 2))
        $rightBar = [Math]::Max(1, $innerWidth - $leftBar - $titlePadded.Length)
        Write-Host "$indent$BorderColor$($Box.TopLeft)$($Box.Horizontal * $leftBar)$($Colors.BrightCyan)$titlePadded$BorderColor$($Box.Horizontal * $rightBar)$($Box.TopRight)$($Colors.Reset)"
    }
    else {
        Write-Host "$indent$BorderColor$($Box.TopLeft)$($Box.Horizontal * $innerWidth)$($Box.TopRight)$($Colors.Reset)"
    }
    
    # Contenu
    foreach ($line in $Content) {
        $cleanLine = $line -replace '\x1b\[[0-9;]*m', ''
        
        # Tronquer les lignes trop longues
        if ($cleanLine.Length -gt $innerWidth) {
            $visibleLen = 0
            $cutIndex = 0
            $inEscape = $false
            
            for ($i = 0; $i -lt $line.Length; $i++) {
                if ($line[$i] -eq [char]27) {
                    $inEscape = $true
                }
                elseif ($inEscape -and $line[$i] -eq 'm') {
                    $inEscape = $false
                }
                elseif (-not $inEscape) {
                    $visibleLen++
                    if ($visibleLen -ge ($innerWidth - 3)) {
                        $cutIndex = $i + 1
                        break
                    }
                }
            }
            
            if ($cutIndex -gt 0) {
                $line = $line.Substring(0, $cutIndex) + "$($Colors.Gray)...$($Colors.Reset)"
                $cleanLine = ($line -replace '\x1b\[[0-9;]*m', '')
            }
        }
        
        $padRight = [Math]::Max(0, $innerWidth - $cleanLine.Length)
        Write-Host "$indent$BorderColor$($Box.Vertical)$($Colors.Reset)$line$(" " * $padRight)$BorderColor$($Box.Vertical)$($Colors.Reset)"
    }
    
    # Ligne inferieure
    Write-Host "$indent$BorderColor$($Box.BottomLeft)$($Box.Horizontal * $innerWidth)$($Box.BottomRight)$($Colors.Reset)"
}

function Draw-SeparatorCentered {
    param(
        [string]$Char = "─",
        [string]$Color = $Colors.Gray,
        [int]$Width = 60
    )
    $consoleWidth = Get-ConsoleWidth
    $paddingLeft = [Math]::Max(0, [Math]::Floor(($consoleWidth - $Width) / 2))
    $indent = " " * $paddingLeft
    Write-Host "$indent$Color$($Char * $Width)$($Colors.Reset)"
}

# ══════════════════════════════════════════════════════════════════════════════
# VERIFICATION MODULE NTFSSECURITY
# ══════════════════════════════════════════════════════════════════════════════

function Test-NTFSSecurityModule {
    Clear-Host
    Write-Host ""

    $command = Get-Command Add-NTFSAccess -ErrorAction SilentlyContinue

    if (-not $command) {
        $modulePath = "C:\Windows\System32\WindowsPowerShell\v1.0\Modules\NTFSSecurity"

        if (Test-Path $modulePath) {
            try {
                Import-Module NTFSSecurity -SkipEditionCheck -ErrorAction Stop
                $command = Get-Command Add-NTFSAccess -ErrorAction SilentlyContinue
            }
            catch {}
        }
    }

    if (-not $command) {
        # Proposer l'installation automatique
        Draw-BoxCentered -Title "Module manquant" -BorderColor $Colors.Yellow -MaxWidth 65 -Content @(
            "",
            " $($Colors.Yellow)Module NTFSSecurity non disponible$($Colors.Reset)",
            "",
            " Le module est requis pour analyser les ACL NTFS.",
            "",
            " $($Colors.Cyan)Tentative d'installation automatique...$($Colors.Reset)",
            ""
        )

        Write-Host ""
        Write-Centered "$($Colors.Cyan)[I]$($Colors.Reset) Installer automatiquement  $($Colors.Cyan)[Echap]$($Colors.Reset) Quitter"
        Write-Host ""

        $waitingInput = $true
        $installModule = $false

        while ($waitingInput) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)

                switch ($key.Key) {
                    "I" {
                        $installModule = $true
                        $waitingInput = $false
                    }
                    "Escape" {
                        $waitingInput = $false
                    }
                }
            }
            Start-Sleep -Milliseconds 50
        }

        if ($installModule) {
            Clear-Host
            Write-Host ""

            Draw-BoxCentered -Title "Installation" -BorderColor $Colors.Cyan -MaxWidth 65 -Content @(
                "",
                " $($Colors.Cyan)Installation du module NTFSSecurity en cours...$($Colors.Reset)",
                "",
                " $($Colors.Gray)Veuillez patienter...$($Colors.Reset)",
                ""
            )

            Write-Host ""

            try {
                # Verifier si NuGet est disponible
                $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
                if (-not $nuget) {
                    Write-Centered "$($Colors.Gray)Installation du provider NuGet...$($Colors.Reset)"
                    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
                }

                # Installer le module
                Write-Centered "$($Colors.Gray)Telechargement et installation de NTFSSecurity...$($Colors.Reset)"
                Install-Module -Name NTFSSecurity -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop

                # Importer le module
                Import-Module NTFSSecurity -SkipEditionCheck -ErrorAction Stop
                $command = Get-Command Add-NTFSAccess -ErrorAction SilentlyContinue

                if ($command) {
                    Write-Host ""
                    Draw-BoxCentered -Title "Succes" -BorderColor $Colors.Green -MaxWidth 65 -Content @(
                        "",
                        " $($Colors.Green)Module NTFSSecurity installe avec succes !$($Colors.Reset)",
                        "",
                        " $($Colors.Gray)Le programme va demarrer...$($Colors.Reset)",
                        ""
                    )
                    Start-Sleep -Seconds 2
                    return $true
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                # Tronquer le message d'erreur si trop long
                if ($errorMessage.Length -gt 55) {
                    $errorMessage = $errorMessage.Substring(0, 52) + "..."
                }

                Clear-Host
                Write-Host ""

                Draw-BoxCentered -Title "Echec installation" -BorderColor $Colors.Red -MaxWidth 65 -Content @(
                    "",
                    " $($Colors.Red)L'installation automatique a echoue$($Colors.Reset)",
                    "",
                    " $($Colors.Gray)Erreur : $errorMessage$($Colors.Reset)",
                    "",
                    " $($Colors.Yellow)Solutions alternatives :$($Colors.Reset)",
                    " $($Colors.Gray)►$($Colors.Reset) Executer PowerShell en Administrateur",
                    " $($Colors.Gray)►$($Colors.Reset) Installer manuellement :",
                    "   $($Colors.Cyan)Install-Module -Name NTFSSecurity -Scope CurrentUser$($Colors.Reset)",
                    "",
                    " $($Colors.Gray)►$($Colors.Reset) Ou copier le module dans :",
                    "   $($Colors.Gray)C:\Windows\System32\WindowsPowerShell\v1.0\Modules\$($Colors.Reset)",
                    ""
                )

                Write-Host ""
                Write-Centered "$($Colors.Gray)Appuyez sur une touche pour quitter...$($Colors.Reset)"
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                exit
            }
        }
        else {
            # L'utilisateur a choisi de quitter
            exit
        }
    }

    return $true
}

# ══════════════════════════════════════════════════════════════════════════════
# AFFICHAGE HEADER ET LEGENDE
# ══════════════════════════════════════════════════════════════════════════════

function Show-Header {
    Clear-Host
    Write-Host ""
    
    # Titre principal centre
    Draw-BoxCentered -Title "ACL Search TUI" -BorderColor $Colors.Cyan -MaxWidth 55 -Content @(
        "",
        "     $($Colors.BrightCyan)Analyse des permissions NTFS$($Colors.Reset)",
        " $($Colors.Gray)→ lit les ACL NTFS$($Colors.Reset)",
        " $($Colors.Gray)→ liste les principaux de sécurité$($Colors.Reset)",
        " $($Colors.Gray)→ affiche leurs droits$($Colors.Reset)",
        ""
    )
    
    Write-Host ""
    
    # Legende centree (sans le label)
    Write-Centered "$($Colors.Modify)Modify$($Colors.Reset)  $($Colors.ReadExec)ReadAndExecute$($Colors.Reset)  $($Colors.Other)Other$($Colors.Reset)"
    Write-Host ""
    
    # Controles centres (sans le label)
    Write-Centered "$($Colors.Cyan)[Entree]$($Colors.Reset) Nouvelle analyse  $($Colors.Cyan)[Echap]$($Colors.Reset) Quitter"
    
    Write-Host ""
    Draw-SeparatorCentered -Width 60
    Write-Host ""
}

# ══════════════════════════════════════════════════════════════════════════════
# FONCTIONS D'AFFICHAGE ACL
# ══════════════════════════════════════════════════════════════════════════════

function Get-ACLColor {
    param([string]$Rights)
    
    if ($Rights -match "Modify") {
        return $Colors.Modify
    }
    elseif ($Rights -match "ReadAndExecute|Write") {
        return $Colors.ReadExec
    }
    else {
        return $Colors.Other
    }
}

function Show-ACLResults {
    param(
        [string]$Path,
        [array]$ACLEntries
    )
    
    # Prefixe ╭── + chemin
    Write-Host "  $($Colors.Cyan)$($Box.TopLeft)$($Box.Horizontal)$($Box.Horizontal)$($Colors.Reset) $($Colors.BrightCyan)$Path$($Colors.Reset)"
    
    if ($ACLEntries.Count -eq 0) {
        Write-Host "      $($Colors.Gray)Aucun droit NTFS trouve$($Colors.Reset)"
    }
    else {
        foreach ($entry in $ACLEntries) {
            $color = Get-ACLColor -Rights $entry.Rights
            $account = $entry.Account
            $rights = $entry.Rights
            
            # Compte et droits de la meme couleur
            $accountPadded = $account.PadRight(50)
            Write-Host "      $color$accountPadded$rights$($Colors.Reset)"
        }
    }
    Write-Host ""
}

# ══════════════════════════════════════════════════════════════════════════════
# ANALYSE ACL
# ══════════════════════════════════════════════════════════════════════════════

function Get-PathACL {
    param([string]$Path)
    
    $results = @()
    
    try {
        $acl = Get-NTFSAccess $Path -ErrorAction Stop | Select-Object Account, AccessRights
        
        foreach ($entry in $acl) {
            $results += @{
                Account = $entry.Account.ToString()
                Rights  = $entry.AccessRights.ToString()
            }
        }
    }
    catch {}
    
    return $results
}

function Start-ACLAnalysis {
    param([string]$Path)
    
    $script:LastResults = @()
    $script:CurrentPath = $Path
    $currentPath = $Path
    $level = 0
    
    Show-Header
    Write-Host "  $($Colors.Cyan)Analyse en cours...$($Colors.Reset)"
    Write-Host ""
    
    while ($currentPath) {
        $level++
        
        # Recuperation des ACL
        $aclEntries = Get-PathACL -Path $currentPath
        
        # Stockage
        $script:LastResults += @{
            Path  = $currentPath
            Level = $level
            ACL   = $aclEntries
        }
        
        # Affichage
        Show-ACLResults -Path $currentPath -ACLEntries $aclEntries
        
        # Obtenir le chemin parent
        $parent = Split-Path -Parent $currentPath
        
        # Conditions d'arret
        if ([string]::IsNullOrEmpty($parent)) {
            Write-Host "  $($Colors.Yellow)► Racine atteinte$($Colors.Reset)"
            break
        }
        
        if ($parent -match '^\\\\[^\\]+$') {
            Write-Host "  $($Colors.Yellow)► Racine serveur atteinte$($Colors.Reset)"
            break
        }
        
        if ($parent -match '^[A-Z]:$') {
            $currentPath = $parent + "\"
            
            $aclEntries = Get-PathACL -Path $currentPath
            $level++
            $script:LastResults += @{
                Path  = $currentPath
                Level = $level
                ACL   = $aclEntries
            }
            Show-ACLResults -Path $currentPath -ACLEntries $aclEntries
            
            Write-Host "  $($Colors.Yellow)► Racine lecteur atteinte$($Colors.Reset)"
            break
        }
        
        $currentPath = $parent
    }
    
    Write-Host ""
    Write-Host "  $($Colors.Green)OK$($Colors.Reset) Analyse terminee - $($Colors.BrightCyan)$level$($Colors.Reset) niveau(x) analyse(s)"
}

# ══════════════════════════════════════════════════════════════════════════════
# OUVERTURE PROPRIETES DE SECURITE
# ══════════════════════════════════════════════════════════════════════════════

function Open-SecurityProperties {
    param([string]$Path)

    try {
        # Utiliser Shell.Application pour ouvrir les proprietes
        $shell = New-Object -ComObject Shell.Application

        # Determiner si c'est un fichier ou un dossier
        $item = Get-Item -Path $Path -ErrorAction Stop

        if ($item.PSIsContainer) {
            # C'est un dossier
            $folder = $shell.NameSpace($Path)
            $folderItem = $folder.Self
            $folderItem.InvokeVerb("Properties")
        }
        else {
            # C'est un fichier
            $parentPath = Split-Path -Parent $Path
            $fileName = Split-Path -Leaf $Path
            $folder = $shell.NameSpace($parentPath)
            $file = $folder.ParseName($fileName)
            $file.InvokeVerb("Properties")
        }

        Write-Host ""
        Write-Centered "$($Colors.Green)Proprietes ouvertes$($Colors.Reset) $($Colors.Gray)- Allez dans Securite > Avance > Effective Access$($Colors.Reset)"
    }
    catch {
        Write-Host ""
        Write-Centered "$($Colors.Red)Erreur : impossible d'ouvrir les proprietes$($Colors.Reset)"
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# SAISIE CHEMIN AVEC VALIDATION
# ══════════════════════════════════════════════════════════════════════════════

function Read-PathInput {
    Write-Host "  $($Colors.BrightCyan)Chemin a analyser :$($Colors.Reset)"
    Write-Host ""
    Write-Host -NoNewline "  $($Colors.Cyan)►$($Colors.Reset) "
    
    Show-Cursor
    $path = Read-Host
    
    if ($path -eq "") {
        return $null
    }
    
    # Nettoyage du chemin
    $path = $path.Trim().Trim('"').Trim("'")
    
    # Validation
    if (-not (Test-Path -Path $path -ErrorAction SilentlyContinue)) {
        Write-Host ""
        
        $displayPath = Get-TruncatedText -Text $path -MaxLength 45
        
        Draw-BoxCentered -Title "Erreur" -BorderColor $Colors.Red -MaxWidth 60 -Content @(
            "",
            " $($Colors.Red)Chemin introuvable ou inaccessible$($Colors.Reset)",
            "",
            " $($Colors.Gray)Chemin : $displayPath$($Colors.Reset)",
            "",
            " $($Colors.Yellow)Verifiez que :$($Colors.Reset)",
            " $($Colors.Gray)►$($Colors.Reset) Le chemin existe",
            " $($Colors.Gray)►$($Colors.Reset) Vous avez les droits d'acces",
            " $($Colors.Gray)►$($Colors.Reset) Le lecteur reseau est connecte",
            ""
        )
        
        return $null
    }
    
    return $path
}

# ══════════════════════════════════════════════════════════════════════════════
# BOUCLE PRINCIPALE
# ══════════════════════════════════════════════════════════════════════════════

function Main {
    Test-NTFSSecurityModule
    
    $running = $true
    
    while ($running) {
        Show-Header
        
        $path = Read-PathInput
        
        if ($path) {
            Start-ACLAnalysis -Path $path
            
            Write-Host ""
            Draw-SeparatorCentered -Width 60
            Write-Centered "$($Colors.Cyan)[V]$($Colors.Reset) Effective Access  $($Colors.Cyan)[Entree]$($Colors.Reset) Nouvelle analyse  $($Colors.Cyan)[Echap]$($Colors.Reset) Quitter"
            Write-Host ""

            $waitingInput = $true
            while ($waitingInput) {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)

                    switch ($key.Key) {
                        "V" {
                            Open-SecurityProperties -Path $path
                        }
                        "Enter" {
                            $waitingInput = $false
                        }
                        "Escape" {
                            $waitingInput = $false
                            $running = $false
                        }
                    }
                }
                Start-Sleep -Milliseconds 50
            }
        }
        else {
            Write-Host ""
            Write-Centered "$($Colors.Cyan)[Entree]$($Colors.Reset) Reessayer  $($Colors.Cyan)[Echap]$($Colors.Reset) Quitter"
            
            $waitingInput = $true
            while ($waitingInput) {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    
                    switch ($key.Key) {
                        "Enter" { $waitingInput = $false }
                        "Escape" { $waitingInput = $false; $running = $false }
                    }
                }
                Start-Sleep -Milliseconds 50
            }
        }
    }
    
    Show-Cursor
    Clear-Host
    Write-Host ""
    Write-Host "  $($Colors.Cyan)ACL Search$($Colors.Reset) - Session terminee"
    Write-Host ""
}

# ══════════════════════════════════════════════════════════════════════════════
# LANCEMENT
# ══════════════════════════════════════════════════════════════════════════════

Main