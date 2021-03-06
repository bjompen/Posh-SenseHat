﻿#####
# Private functions

Function WriteByteArrayToMatrix {
    Param(
        [Parameter(Mandatory = $true)]
        [Byte[]]$PixelList
    )

    $Writer = [System.IO.BinaryWriter]::new([System.IO.File]::Open('/dev/fb1', [System.IO.FileMode]::Open))
    
    for ($i = 0 ; $I -lt $PixelList.Length  ; $i ++) { 
        $Null = $Writer.Seek($i, [System.IO.SeekOrigin]::Begin) 
        $Null = $Writer.Write([byte]$PixelList[$i]) 
    }

    $Writer.Close()
    $Writer.Dispose()
}

Function ConvertToByteArray{ 
    param(
        [UInt16[]]$source
    )

    [byte[]]$arrayAsByte = New-Object -TypeName Byte[] -ArgumentList ($source.Length * 2)

    [System.Buffer]::BlockCopy($source, 0, $arrayAsByte, 0, $arrayAsByte.Length)
    $arrayAsByte
}

Function GetAvailableFonts {
    Param(
        [String]$SearchPath = "$PSScriptRoot\fonts"
    )
    Get-ChildItem $SearchPath\*.bdf -ErrorAction SilentlyContinue | foreach {
        New-Object -TypeName psobject -Property @{
            'Name' = $_.BaseName
            'FontPath' = $_.FullName
        }
    }
}

Function ParseBitmapFont {
    Param(
        [Parameter(Mandatory=$True,
                   ValueFromPipelineByPropertyName=$true
        )]
        [String]$FontPath
    )

    $FileContent = Get-Content $FontPath
    $PropertyLastLine = $FileContent | select-string STARTCHAR | select-Object -first 1 -ExpandProperty LineNumber

    $FontProperty = @{}
    $FileContent[0..$PropertyLastLine] -replace ' ','=' | Where-Object {$_ -like "*=*" } | ConvertFrom-StringData | foreach { $FontProperty.($_.Name) = $_.value}
    
    $Char = @{}
    $CharLineNumbers = $FileContent | Select-String "ENCODING" | Select-Object -ExpandProperty LineNumber | Where {$_ -gt $PropertyLastLine}
    
    Foreach ($StartLine in $CharLineNumbers) {
        $LineContent,$LineInt = $FileContent[($StartLine -1)] -split ' ' 
        IF (([int]$LineInt -ge 32) -and ([int]$LineInt -le 126)) {
            $CurrentChar = [char][int]$lineint
            do {
                $StartLine++
            } 
            until ($FileContent[$StartLine] -like "BITMAP")
            $EndLine = $StartLine
            do {
                $EndLine++
            } 
            until ($FileContent[$EndLine] -like "ENDCHAR")
            $CurrentCharLayout = $FileContent[($StartLine + 1)..($EndLine - 1)] -join ','
            
            $Char.Add($CurrentChar,$CurrentCharLayout)
        }
    }

    $Char
}

Function ConvertTextToByteArray {
    Param(
        [string]$Text,
        [hashtable]$BitmapFont,
        [UInt16]$ForeGroundColor,
        [UInt16]$BackGroundColor
    )

    $Return = [System.Collections.ArrayList]::new()
    $CharArray = $Text.ToCharArray()
    foreach ($Char in $CharArray) {
        $Hex = ($BitmapFont.$char -split ',')[1..8]
        $ByteArray = $Hex | foreach {
            $ThisBin = [Convert]::ToString((Invoke-Expression "0x$_"),2).PadLeft(8, "0")
            $ThisBin[0..7] | foreach {
                Switch ($_) {
                    "0" { [UInt16]"$BackGroundColor" }
                    "1" { [UInt16]"$ForeGroundColor" }
                }
                
            }
        }
        
        $Null = $return.Add($ByteArray)
    }

    $return
}

#####
# Public functions

Function Set-MatrixWithRainbow {
    $Color = [UInt16]32768
    [UInt16[]]$PixelList = $Color
    1..15 | foreach {
        $PixelList += $Color -bor ($Color -shr 1)
        $Color = $PixelList[-1]
    }
    1..16 | foreach {
        $PixelList += $Color -shr 1
        $Color = $PixelList[-1]
    }
    
    [UInt16[]]$PixelList += $PixelList[($PixelList.Length -1)..0]
    
    $PixelListByte = ConvertToByteArray -source $PixelList
    WritebyteArrayToMatrix -PixelList $PixelListByte
}

Function Set-MatrixWithSingleColor { 
    Param(
        [Parameter(Mandatory = $true, 
            ValueFromPipeline = $true, 
            ValueFromPipelineByPropertyName = $true, 
            Position = 0
        )]
        [ValidateRange(0,31)]
        [UInt16]$Red,

        [Parameter(Mandatory = $true, 
            ValueFromPipeline = $true, 
            ValueFromPipelineByPropertyName = $true, 
            Position = 0
        )]
        [ValidateRange(0,63)]
        [UInt16]$Green,

        [Parameter(Mandatory = $true, 
            ValueFromPipeline = $true, 
            ValueFromPipelineByPropertyName = $true, 
            Position = 0
        )]
        [ValidateRange(0,31)]
        [UInt16]$Blue
    )

    Begin {
        $PixelListInt = @()
    }

    Process {
        for ($I = 0 ; $I -lt 64 ; $I++ ) {
            [UInt16[]]$PixelListInt += [UInt16]( ([UInt16]$Red -shl 11) -bor ([UInt16]$Green -shl 5) -bor ([UInt16]$Blue) )
        }

        Try {
            $PixelListByte = ConvertToByteArray -source $PixelListInt
            WritebyteArrayToMatrix -PixelList $PixelListByte
        }
        catch {
            Write-Error 'Failed to write output to screen.'
        }
    }
}

Function Write-SenseHatMatrix {
    Param(
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [String]$Text,

        [String]$Font = 'cherry-10-b',
        [UInt16]$BackgroundColor = 0,
        [UInt16]$ForegroundColor = 63488,
        [Int]$TextSpeed = 1,
        [Int]$Loop = 1
    )

    $FontCache = GetAvailableFonts | Where-Object -Property Name -eq $Font | ParseBitmapFont
    $Pages = ConvertTextToByteArray -Text $Text -BitmapFont $FontCache -ForeGroundColor $ForegroundColor -BackGroundColor $BackgroundColor
    
    1..$Loop | Foreach { 
        foreach ($Page in $Pages) {
            $ByteArray = ConvertToByteArray -source $Page
            WritebyteArrayToMatrix -PixelList $ByteArray
            Start-Sleep -Seconds $TextSpeed
        }
    }
    Set-MatrixWithSingleColor -Red 0 -Green 0 -Blue 0    
}

Function Get-RGB565Color {
    param(
        [Parameter(Mandatory=$True)]
        [ValidateSet('Red','Green','Blue','Yellow','Orange','Purple','Pink','LightBlue','LightRed','LightGreen','LightYellow','DarkBlue','DarkRed','DarkGreen','DarkYellow','grey','white','black','darkpink','DarkOrange')]
        [string]$Color
    )

    Switch ($Color) {
        'Red'         {$Red = 31; $Green = 0; $Blue = 0}
        'Green'       {$Red = 0; $Green = 63; $Blue = 0}
        'Blue'        {$Red = 0; $Green = 0; $Blue = 31}
        'Yellow'      {$Red = 31; $Green = 63; $Blue = 0}
        'Orange'      {$Red = 31; $Green = 32; $Blue = 8}
        'Purple'      {$Red = 16; $Green = 0; $Blue = 31}
        'Pink'        {$Red = 31; $Green = 0; $Blue = 31}
        'LightBlue'   {$Red = 0; $Green = 63; $Blue = 31}
        'LightRed'    {$Red = 31; $Green = 32; $Blue = 16}
        'LightGreen'  {$Red = 16; $Green = 63; $Blue = 16}
        'LightYellow' {$Red = 31; $Green = 63; $Blue = 16}
        'DarkBlue'    {$Red = 0; $Green = 0; $Blue = 16}
        'DarkRed'     {$Red = 16; $Green = 0; $Blue = 0}
        'DarkGreen'   {$Red = 0; $Green = 16; $Blue = 0}
        'DarkYellow'  {$Red = 16; $Green = 32; $Blue = 0}
        'grey'        {$Red = 24; $Green = 48; $Blue = 24}
        'white'       {$Red = 31; $Green = 63; $Blue = 31}
        'black'       {$Red = 0; $Green = 0; $Blue = 0}
        'darkpink'    {$Red = 16; $Green = 0; $Blue = 8}
        'DarkOrange'  {$Red = 26; $Green = 26; $Blue = 0}
    }
    
    
    New-Object -TypeName psobject -Property @{
        'Red' = $Red
        'green' = $green
        'blue' = $blue
    }
}

# Export only the functions using PowerShell standard verb-noun naming.
# Be sure to list each exported functions in the FunctionsToExport field of the module manifest file.
# This improves performance of command discovery in PowerShell.
Export-ModuleMember -Function *-*
