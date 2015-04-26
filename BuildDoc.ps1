##
## PoShDoc: Simply PowerShell module README documentation generator
## URL: https://github.com/DuFace/PoShDoc
## Copyright (c) 2014-2015 Kier Dugan
##

<#
.SYNOPSIS

GitHub-Flavoured Markdown documentation converter for PowerShell command help.


.DESCRIPTION

This script uses the structure returned by `Get-Help` to generate GFM that can
be directly embedded in a README.md file.  A template file must be specified
that invokes the conversion at the appropriate places.  Consider the following
Markdown snippet as an example:

    # Commands
    {% MyFirstCommand %}
    {% MySecondCommand %}

This would result in Markdown containing a level 1 heading, followed by two
command descriptions generated by calling `Get-Help` on each one.  At present,
the output cannot be easily customised and the script *must* be able to resolve
the command names.  Module files can be imported by the script if necessary.


.PARAMETER TemplateFile

Template file containing look-up directives of the form `{% <Command> %}`.


.PARAMETER OutputFile

Generated Markdown will be written into this file using UTF8 encoding without a
BOM.


.PARAMETER Modules

List of module files (*.psm1) to import.


.LINK

https://github.com/DuFace/PoShDoc
#>
[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(Mandatory=$true)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [String]
    $TemplateFile,

    [Parameter(Mandatory=$false)]
    [String]
    $OutputFile,

    [Parameter(Mandatory=$false)]
    [Alias("Module")]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [String[]]
    $Modules
)


## Table Descriptors -----------------------------------------------------------
function HeaderCell {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [String]
        $Name,

        [Parameter(Mandatory=$false)]
        [Switch]
        $Centre,

        [Parameter(Mandatory=$false)]
        [Switch]
        $Right
    )

    process {
        # Decode alignment
        $align = "Left"
        if ($Centre) {
            $align = "Centre"
        } elseif ($Right) {
            $align = "Right"
        }

        # Create a new object to return
        $cell = New-Object System.Object
        $cell | Add-Member -Type NoteProperty -Name "Name" -Value $Name
        $cell | Add-Member -Type NoteProperty -Name "Alignment" -Value $align
        $cell
    }
}

function Header {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [ScriptBlock]
        $Cells
    )

    process {
        # Create a new object
        $row = New-Object System.Object
        $row | Add-Member -Type NoteProperty -Name "Type" -Value "Header"
        $row | Add-Member -Type NoteProperty -Name "Cells" -Value (&$Cells)
        $row
    }
}

function Cell {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [String]
        $Content
    )

    process {
        $content
    }
}

function Row {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [ScriptBlock]
        $Cells
    )

    process {
        # Create a new object
        $row = New-Object System.Object
        $row | Add-Member -Type NoteProperty -Name "Type" -Value "Row"
        $row | Add-Member -Type NoteProperty -Name "Cells" -Value (&$Cells)
        $row
    }
}

function Describe-Table {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [ScriptBlock]
        $Content
    )

    process {
        $table = New-Object System.Object
        $rows  = @()

        # Build the table
        &$Content | foreach {
            $row = $_
            switch ($row.Type) {
                "Header" {
                    $table | Add-Member -Type NoteProperty -Name "Columns" `
                        -Value $row.Cells
                }

                "Row" {
                    $rows += ,$row.Cells
                }
            }
        }

        # Add the rows
        $table | Add-Member -Type NoteProperty -Name "Rows" -Value $rows

        # Return the constructed table
        return $table
    }
}


## Table Builder Functions -----------------------------------------------------
function ColumnCharWidths($table) {
    # Calculate the maximum length of the cell in each row of the data
    $lengths = for ($i = 0; $i -lt $table.Columns.Length; $i++) {
        ($table.Rows | foreach { $_[$i].Length } |
            Measure-Object -Maximum).Maximum
    }

    # Factor in the headings
    for ($i = 0; $i -lt $table.Columns.Length; $i++) {
        [Math]::Max($lengths[$i], $table.Columns[$i].Name.Length)
    }
}

function MakeHeaderDelimeter($width, $alignment) {
    # Make the actual bunch of dashes
    $delim = '-' * $width

    # Replace the end points
    if ($alignment -eq 'Left' -or $alignment -eq 'Centre') {
        $delim = ':' + $delim.Substring(1, $width - 1)
    }

    if ($alignment -eq 'Centre' -or $alignment -eq 'Right') {
        $delim = $delim.Substring(0, $width - 1) + ':'
    }

    # Return the delimeter
    return $delim
}

function MakeRow($cells, $widths) {
    $formattedCells = for ($i = 0; $i -lt $cells.Length; $i++) {
        [string]::Format("{0,-$($widths[$i])}", $cells[$i])
    }
    return "| $($formattedCells -join ' | ') |"
}

function Format-MarkdownTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Table
    )

    process {
        $mdtable  = @()

        # Compute the largest string in each column
        $lengths = ColumnCharWidths $table

        # Add the header row
        $mdtable += MakeRow ($table.Columns | foreach { $_.Name }) $lengths

        # Add the delimeter row
        $delims = for ($i = 0; $i -lt $table.Columns.Length; $i++) {
            MakeHeaderDelimeter $lengths[$i] $table.Columns[$i].Alignment
        }
        $mdtable += MakeRow $delims $lengths

        # Add each content row
        foreach ($row in $table.Rows) {
            $mdtable += MakeRow $row $lengths
        }

        return $mdtable
    }
}


## Get-Help Parsers ------------------------------------------------------------

function ConvertCommandHelp($help) {
    $doc = ""

    # If the command name is a script, strip off the path
    $cmdName = if ($help.Name -like "*.ps1") {
        (Get-Item $help.Name).Name
    } else {
        $help.Name
    }

    # Tidy up the syntax line to make it fit on one line
    $cmdSyntax = ($help.syntax | Out-String).Trim()
    $cmdSyntax = $cmdSyntax.Replace("`r", "")
    $cmdSyntax = $cmdSyntax.Replace("`n", "")

    # If the command is a script, swap the command name with the scriptname
    if ($help.Name -like "*.ps1") {
        $cmdSyntax = $cmdSyntax.Replace($help.Name, $cmdName)
    }

    # Generate a sane slug for the anchor tag
    $cmdSlug = $cmdName -replace '\W+','-'

    # Open with an anchor, sub-heading, and synopsis
    $doc += "<a id=`"$cmdSlug`"></a>`r`n"
    $doc += "## $cmdName`r`n"
    $doc += "`r`n"
    $doc += '```' + "`r`n"
    $doc += "$cmdSyntax`r`n"
    $doc += '```' + "`r`n"
    $doc += "`r`n"
    $doc += ($help.Synopsis | Out-String).Trim() + "`r`n"
    $doc += "`r`n"

    # Add detail
    $doc += "### Description`r`n"
    $doc += ($help.description | Out-String).Trim() + "`r`n"

    # Add parameters
    $paramTable = Describe-Table {
        Header {
            HeaderCell "Parameter"
            HeaderCell "Type" -Centre
            HeaderCell "Description"
        }

        foreach ($param in $help.parameters.parameter) {
            $paramName = ($param.name | Out-String).Trim()
            $paramType = ($param.type.name | Out-String).Trim()
            $paramDesc = ($param.description | Out-String).Trim()

            if ($paramType -eq 'SwitchParameter') {
                $paramType = 'Switch'
            }

            if ($paramDesc) {
                # Sanitise the description
                $paramDesc = ($paramDesc -split "`r?`n" |
                              foreach { $_.Trim() }) -join ' '

                Row {
                    Cell $paramName
                    Cell $paramType
                    Cell $paramDesc
                }
            }
        }
    }
    if ($paramTable.Rows.Length) {
        $doc += "`r`n### Parameters`r`n"
        $doc += (Format-MarkdownTable $paramTable) -join "`r`n"
        $doc += "`r`n"
    }

    return $doc
}


## Actual documentation generator ----------------------------------------------

# Import all the modules to document
foreach ($mod in $Modules) {
    Import-Module $mod -Force
}

# Load the template file
$srcdoc = Get-Content $TemplateFile

# Magic callback that does the munging
$callback = {
    if ($args[0].Groups[0].Value.StartsWith('\')) {
        # Escaped tag; strip escape character and return
        $args[0].Groups[0].Value.Remove(0, 1)
    } else {
        # Look up the help and generate the Markdown
        ConvertCommandHelp (Get-Help $args[0].Groups[1].Value)
    }
}
$re = [Regex]"\\?{%\s*(.*?)\s*%}"

# Generate the readme
$readme = $srcdoc | foreach { $re.Replace($_, $callback) }

# Output to the appropriate stream
if ($OutputFile) {
    $OutputFile = Join-Path (Get-Location) $OutputFile
    $utf8Encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($OutputFile, $readme, $utf8Encoding)
} else {
    $readme | Out-Host
}

