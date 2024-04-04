using namespace System.Management.Automation
enum severityMap {
    EMERGENCY = 0
    ALERT     = 1
    CRIT      = 2
    ERROR     = 3
    WARN      = 4
    NOTICE    = 5
    INFO      = 6
    DEBUG     = 7
}

class LogSetting {
    [String] $Color
    [String] $AnsiId
    [String] $Type

    LogSetting( $s ){

        # Used to assign different configuration options
        $colorName, $id, $sevType = Switch -regex ( $s ){

            'EMERGENCY' { 'Red'        ; "`e[91m" ; 'error' }
            'ALERT'     { 'Red'        ; "`e[91m" ; 'error' }
            'CRIT'      { 'DarkRed'    ; "`e[31m" ; 'error' }
            'ERROR'     { 'Magenta'    ; "`e[95m" ; 'error' }
            'WARN'      { 'DarkYellow' ; "`e[93m" ; 'warning' }
            'NOTICE'    { 'Cyan'       ; "`e[96m" ; 'warning' }
            'INFO'      { 'Green'      ; "`e[92m" ; 'information' }
            'DEBUG'     { 'Gray'       ; "`e[90m" ; 'information' }
        }

        $this.color     = $colorName
        $this.ansiId    = $id
        $this.type      = $sevType
    }
}

class LogPath {
    [String] $Parent
    [String[]] $Path
    [PSObject[]] $Attachment

    LogPath( $p, $l ){
        $this.parent = $p
        $this.path = $l
    }
}

class RationalLog {
    [String] $Time
    [DateTime] $Date
    [String] $Instance
    [String] $Severity
    [String] $Project
    [String] $Title
    [String[]] $Group
    [String[]] $Collection
    [String] $Message
    [LogSetting] $Settings
    [PSObject[]] $Attachment
    [String] $Source
    [String[]] $Path

    RationalLog( $timeFormat, $p, $t, $g, $c, $s, $m, $l, $a, $f ){

        $dateTime = Get-Date
        $timeStr = if( $timeFormat -eq 'epoch' ){ GetEpochTime $dateTime }else{ $dateTime.toString('yyyy-MM-dd HH:mm:ss') }
        
        $this.time = $timeStr
        $this.date = $dateTime
        $this.instance = $global:pid
        
        $this.project = $p
        $this.title = $t
        $this.severity = $s 
        $this.group = $g
        $this.collection = $c
        $this.message = $m
        $this.settings = $l
        $this.attachment = $a
        $this.source = $f
    }

    RationalLog(){}
}

function FormatHostOutput( $outMessage, $output ){

    <#
    .SYNOPSIS
        This function configures any environment settings for the output object which is sent to the host display
    #>
    
    # Backwards compatibility for < PS7 display modes
    if( $psVersionTable.psEdition -eq 'Desktop' ){

        [HostInformationMessage]@{
            ForeGroundColor = $output.settings.color
            Message = $outMessage
        }
    }
    # Settings for using ansi escape sequences
    else{

        $output.settings.ansiId + $outMessage + "`e[39m"
    }
}

function FormatOutputString($log){
    <#
    .SYNOPSIS
        This function is used to format the output that is sent to the host/console
    #>

    # This is a complete unnecessary bit to center align text within the log boxes
    $outSev = $log.severity.toUpper().padright(6)
    $outTitle = $log.title.padleft(10-[int]((10-$log.title.length)/2)).padright(10).substring(0,10)

    # This is where we generate the output string which is sent to the primary host
    if( [String]::IsNullOrEmpty( $log.group )){

        "[{0}][{1}][{2}][{3}]" -f $log.time,$outSev,$outTitle,$log.message
    }
    else{

        $groupSet = if( ($log.group|Measure-Object).count -gt 1 ){ $log.group | forEach-Object{ "{$_}" }}else{ $log.group }
        "[{0}][{1}][{2}][{3}][{4}]" -f $log.time,$outSev,$outTitle,($groupSet -join ''),$log.message
    }

}

function GetEpochTime($date) {
    
    <#
    .SYNOPSIS
        This is just a simple way of calculating the epochtime string for a specified datetime object
    #>
    
    $date = if( !$PSBoundParameters['date]'] ){ Get-Date }

    [System.Math]::Truncate(( Get-Date -Date ($date).ToUniversalTime() -UFormat %s ))
}


function NewEventLogEntry( $log ){

    <#
    .SYNOPSIS
        This function will generate a new Windows Event entry to the local events in the 'Application' log
    #>

    try{

        New-EventLog -LogName Application -Source $log.projectName -ErrorAction Stop
    }
    catch [System.InvalidOperationException]{ 
        
        # TODO: Improve method for determining if a log source exists
        # This behavior occurs because we have no way to determine if a log source exists and failure is expected if a log type exists
    }
    catch {

        Write-Warning "Unable to create new WinEvent source '$($log.projectName)' (an Event source may already exist): $($_.exception.message)"
    }

    try{

        $eventLog = @{
            LogName   = 'Application'
            Source    = $log.projectName
            Message   = $log.message
            EventId   = 1337
            EntryType = $log.settings.type
        }
        Write-EventLog @eventLog
    }
    catch [System.Security.SecurityException]{

        Write-Warning "WinEvent source '$($log.projectName)' does not exist. You will need admin access to generate a new source: $($_.exception.message)"
    }
    catch{

        Write-Warning "An unknown error occurred when attemtping to create a new WinEvent: $($_.exception.message)"
    }
}


function OutputLogFile( $OutputType, $OutputFilePath, $hostMessage, $Output ){
    
    <#
    .SYNOPSIS
        This function will configure the output log file and will adjust output setting depending on user selection
    #>
    
    Switch( $outputType ){

        'txt' {

            forEach( $outputPath in $outputFilePath.path ){ 
                
                try{
                    
                    $hostMessage | Out-File -FilePath $outputPath -Append -ErrorAction 'stop'
                    $output.path += $outputPath
                }
                catch{

                    Write-Warning "Failed to save to '$outputPath': $_"
                }
            }
        }

        'csv' {
            
            forEach( $outputPath in $outputFilePath.path ){ 

                try{
                    $output | Select-Object Time,Instance,Severity,Title,Group,Message,Source,@{n = 'Attachment';e = { $_.attachment | ConvertTo-Json}} | 
                        Export-Csv -NoTypeInformation -Path $outputpath -Append -ErrorAction 'stop'
                    $output.path += $outputPath
                }
                catch{

                    Write-Warning "Failed to save to '$outputPath': $_"
                }
            }
        }

        # TODO: Implement json file creation/manipulation

        'log' {

            $type = Switch -regex( [Int][SeverityMap]::($severity.toUpper()) ){

                { $_ -lt 4 } { 3 } # Higher than warning
                { $_ -eq 4 } { 2 } # Warning
                default      { 1 } # All other severity
            }

            # We need to use a specialized text formatting for SCCMTrace log files
            $strTime = "$($output.date.toString('HH:mm:ss')).$($output.date.millisecond)+0000"
            $strMsg = if( [String]::IsNullOrEmpty($output.group) ){

                "$($output.severity.toUpper())::$($output.message)"
            }
            else{
                "$($output.severity.toUpper())::[$($output.group -join ':' )]::$($output.message)"
                
            }
            
            if( $attachment ){
                
                $strAttach = "`n" + ( $output.attachment | ConvertTo-Json -ErrorAction SilentlyContinue )
                
                $strMsg += $strAttach

                if( $strMsg.length -gt 8000 ){ $strMsg = $strMsg.substring(0,8000) }
            }
            $line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="{5}" file="{6}">'
            $outLine = $line -f $strMsg,$strTime,$($output.date.tostring('MM-dd-yyyy')),$output.title,$type,$pid,$output.file
            forEach( $outputPath in $outputFilePath.path ){ 

                try{
                    
                    $outLine | Out-File -FilePath $outputPath -Append -Encoding Utf8 -ErrorAction 'stop'
                    $output.path += $outputPath
                }
                catch{

                    Write-Warning "Failed to save to '$outputPath.path': $_"
                    $setPath = @{
                        Path = $env:TEMP
                        ProjectName = $output.project 
                        OutputType = 'log'
                    }    
                    $tempPath = SetOutputPath @setPath
                    $outLine | Out-File -FilePath ([String]$tempPath.path) -Append -Encoding Utf8
                    Write-Warning "Output path update to $($tempPath.path)"
                    $output.Path += $tempPath.path
                }
            }
        }
    }
}

function SaveAttachment( $path, $log ){

    <#
    .SYNOPSIS
        This function deals with saving the log output object to a file as json
    #>

    if( !(Test-Path "$($Path.parent)\attachments")){

        New-Item -Path $Path.parent -ItemType Directory -Name attachments | Out-Null
    }

    $filetime = GetEpochTime
    $attachPath = "$Path\attachments\${filetime}_$($log.projectName).json"
    ($log.attachment | ConvertTo-Json ) | Out-File -FilePath $attachPath -Encoding Utf8
}

function SetLogVar( $output, $logVariable ){
    <#
    .SYNOPSIS
        This function deals with saving a new log variable to the global scope
    #>
    
    try{

        Write-Debug $logVariable
        $var = Get-Variable -Name $logVariable -Scope global -ErrorAction Stop
    }
    catch [System.Management.Automation.ItemNotFoundException]{
    
        Write-Verbose "Creating new output variable called '$logVariable'"
        [Collections.ArrayList]$tempVar = @()
    }
    catch [System.Management.Automation.ArgumentTransformationMetadataException] {

        Write-Warning "Unable to add a new value to '$logVariable'. Please clear the variable and try again."
    }
    catch{

        Write-Warning "Unable to save log entry to '$logVariable'. Clear the variable and try again."
        continue
    }
    
    if( $var ){

        [Collections.ArrayList]$tempVar = $var.value 
    }
    try{

        $tempVar.Add( $output ) | Out-Null
    }
    catch [System.Management.Automation.ArgumentTransformationMetadataException]{

        Write-Warning "Wrong data type has been set for logVariable $logVariable"
    }
    catch{

        Write-Warning "An unknown error has occurred:`n$($_)"
    }

    try{

        Set-Variable -Name $logvariable -Value $tempVar -Scope global -Force
    }
    catch{

        Write-Warning "Unable to save log entry to '$logvariable'. An unknown error has occurred:`n$($_)"
    }
}

function SetOutputPath {

    <#
    .SYNOPSIS
        This function will configure the project folder and manages and any settings pertaining to the output file name
    #>
    
    [cmdletbinding()]

    param(
        $Path,
        $Collection,
        $ProjectName,
        $OutputType,
        $EnableLogRotation
    )

    $date = Get-Date 

    # Creates a new log directory if there is not already one
    $projpath = Join-Path $path $projectname
    if( ! ( Test-Path $projpath )){

        Write-Verbose "No project folder discovered at $projpath. A new one will now be created"
        New-Item -ItemType Directory -Name $projectname -Path $path | Out-Null
    }

    # Sets the output project/collection folder and logs
    $fileName = if( $Collection ){

        forEach( $col in $collection ){

            if( $col -eq 'default' ){
                
                $projectName + '.' + $outputType
            }
            else{

                $projectName + '_' + $col + '.' + $outputType 
            }
        }
    }
    else{

        $projectName + '.' + $outputType 
    }

    # Configures the file output path based on the log type assigned
    $files = forEach( $file in $fileName ){
        
        Switch( $enablelogrotation ){
            $true   { Join-Path $projpath $file }
            default { Join-Path $projpath "$($date.toString('yyyyMMdd'))_$file" }
        }
    }

    [LogPath]::New( $projPath, $files )
}

function UpdateLogRotation( $path, $rotationLogCount, $logSizeMB ){

    <#
    .SYNOPSIS
        This function will update an existing rotation log file if it exceeds set thresholds
    #>

    forEach( $outputPath in $path.path ){

        if( (Test-Path $outputpath) ){

            if( (Get-Item $outputpath).length / 1MB -gt $logsizeMB ){

                if( Test-Path "$outputpath.$($rotationlogcount - 1)" ){

                    Write-Verbose "Removing oldest log file $outputpath.$($rotationlogcount - 1)"
                    Remove-Item -Path "$outputpath.$($rotationlogcount - 1)" -Force
                }

                for( $i = 1; $i -le $rotationlogcount; $i += 1 ){

                    if( Test-Path "$outputpath.$($rotationlogcount - $i)" ){
                        
                        Write-Verbose "Rotating $outputpath.$($rotationlogcount - $i) to $outputpath.$($rotationlogcount - $i + 1)"
                        Rename-Item -Path "$outputpath.$($rotationlogcount - $i)" -NewName "$outputpath.$($rotationlogcount - $i + 1)" -Force
                    }
                    else{

                        Write-Verbose "No file found called $outputpath.$($rotationlogcount - $i) to rotate"
                    }
                }

                Write-Verbose "Rotating $outputpath to $outputpath.0"
                Rename-Item -Path $outputpath -NewName "$outputpath.0" -Force
            }
        }
    }
}

function Set-Log {

    <#
    .SYNOPSIS
        This function will set the default logging settings which will be used throughout a script
    
    .DESCRIPTION
        This function will set the default logging settings which will be used throughout a script. This utilizes the $psdefaultparametervalues
        variable so it will not be carried to a new session or be available within an imported module unless it is configured to 
        replicate the variable within the module/session.

    .PARAMETER ProjectName
        This parameter sets the project name that will accompany the exported file as well as the parent folder that is created
        for the logging folders

    .PARAMETER Path
        This is the export path where the project folder will be created. 

        NOTE: A subfolder for the project will be created below this path and the logging files will not be saved directly to this folder

    .PARAMETER OverWriteDefaults
        This will need to be used should any previous logging settings have been saved to the current powershell session. This will
        completely wipe out the previous settings

    .PARAMETER Scope
        This indicates the scope of the PSDefaultParameterValues settings if they do not need to be saved as Global within a script

    .PARAMETER LogSizeMB
        This parameter can be used only for rotation logs but will set the maximum log size for a log before it rolls into using the 
        next available logging file

    .PARAMETER RotationLogCount
        This is the number of log files which are kept local to the system. The oldest file will be purged and deleted once the
        number or $RotationLogCount is exceeded

    .INPUTS
        [System.String]

    .OUTPUTS
        No output is expected but will update the values saved to $PSDefaultParameterValues

    .EXAMPLE
        PS> Set-Log -ProjectName ProjectX -Path c:\Scripts\Logs -RotationLogCount 5 -LogSizeMB 20 -OverWriteDefaults

        This will create a new series or rotation log files called 'ProjectX.log' (and when rotated: ProjectX.0, ProjectX.1, etc)
        All log files will be within the folder 'C:\Script\Logs\ProjectX'
        Maximum number of log files is 5 files with a maximum size of 20MB each

    .NOTES
        This function should be used in conjunction with the Write-Log function and currently only outputs to a csv formatted file
    #>

    [cmdletbinding(DefaultParameterSetName = 'DatedLog')]

    param(
        [Parameter( ParameterSetName = 'DatedLog')]
        [Parameter( ParameterSetName = 'LogRotation')]
        [String] $ProjectName,

        [Parameter()]
        [String] $Collection,

        [Parameter()]
        [String] $Group,

        [Parameter( ParameterSetName = 'DatedLog' )]
        [Parameter( ParameterSetName = 'LogRotation' )]
        [String] $Path = "${env:TEMP}",

        [Parameter()]
        [Alias('OverwriteDefaults')]
        [Switch] $Force = $false,

        [Parameter()]
        [Switch] $ResetAllDefaults = $false,

        [Parameter()]
        [ValidateSet('global','script')]
        [String] $Scope = 'global',

        [Parameter()]
        [ValidateSet('EMERGENCY','ALERT','CRIT','ERROR','WARN','NOTICE','INFO','DEBUG')]
        [String] $DisplaySeverityLevel = 'info',

        [Parameter()]
        [ValidateSet('csv','log','txt')]
        [String] $OutputType = 'log',

        [Parameter( ParameterSetName = 'LogRotation' )]
        [Switch] $EnableLogRotation = $false,

        [Parameter( ParameterSetName = 'LogRotation' )]
        [ValidateRange(1,5000)]
        [Int] $LogSizeMB = 200,

        [Parameter( ParameterSetName = 'LogRotation' )]
        [ValidateRange(1,20)]
        [Int] $RotationLogCount = 5,

        [Parameter()]
        [Switch] $PassThru = $false
    )

    $staticParam = @('Force','ResetAllDefaults','passThru','verbose','debug','erroraction','warningaction',
        'informationAction','errorVariable','warningVariable','informationVariable','outVariable',
        'outBuffer','pipelineVariable')

    $variables = forEach( $item in $myInvocation.myCommand.Parameters.keys.where{$_ -notIn $staticParam} ){ 

        try{ 
            
            Get-Variable -Name $item -ErrorAction 'stop' 
        }
        catch{ 
            
            Write-Warning "Error retrieving settings for '$item'"
            continue 
        }
    }

    Write-Debug ( $variables | ConvertTo-Json )

    # This will go through and remove any of the previously assigned settings
    foreach( $var in $variables.where{ $_.value -ne 0 } ){

        $varName = "Write-IrrationalLog:" + $var.name

        # Debug current variable details
        Write-Debug $varName
        if( ![String]::IsNullOrEmpty($global:PSDefaultParameterValues.$varName) ){
            Write-Debug ("Current Settings:" + $global:PSDefaultParameterValues.$varName) 
        }
        else{ 
            Write-Debug 'Current Settings: null' 
        }
        
        Write-Debug "New Settings: $( $var | ConvertTo-Json -WarningAction 'silentlyContinue' )"
        
        # Resets all saved settings
        if( $PSBoundParameters['ResetsAllDefaults'] ){

            Write-Verbose "Removing $varName"
            $global:psdefaultparametervalues.remove("$varName")
        }
        
        # no changes required if default value is already assigned
        elseif( $var.value -eq $global:PSDefaultParameterValues.$varName -OR [String]::IsNullOrEmpty($var.value) ){
            
            Write-Verbose "No updates required for '$varName'"
            continue
        }

        # remove the current assigned value
        elseif( $PSBoundParameters['force'] -AND $PSBoundParameters[$var.name]){

            Write-Verbose "Removing current default parameter settings for '$varName'"
            $global:psdefaultparametervalues.remove("$varName")
        }

        if(![String]::IsNullOrEmpty( $var.value )){

            try{

                $global:PSDefaultParameterValues.Add($varName,$var.value)
                Write-Verbose "Settings have been added for '$($varName)' => $($var.value)"
            }
            catch [System.ArgumentException]{
            
                Write-Warning "Default parameter is set for $varName=='$($global:PSDefaultParameterValues.$varName)'. Use -Force to overwrite"
            }
            catch {

                Write-Error "An unknown error has occurred when retrieving the variable $varName"
                continue
            }
        }
    }

    $outputpath = Switch ($psCmdlet.ParameterSetname ){

        'LogRotation'      {
            # <projectName>\<projectName>.<outputType>
            $dest = "{0}\{1}.{2}" -f 
                $global:PSDefaultParameterValues['Write-IrrationalLog:projectName'],
                $global:PSDefaultParameterValues['Write-IrrationalLog:projectName'],
                $global:PSDefaultParameterValues['Write-IrrationalLog:outputtype']
            Join-Path $path $dest
        }
        'datedlog'         {
            $date = Get-Date -f 'yyyyMMdd' 

            # <projectName>\<date>_<projectName>.<outputType>
            $dest = "{0}\{1}.{2}" -f 
                $global:PSDefaultParameterValues['Write-IrrationalLog:projectName'],
                ${date} + '_' + $global:PSDefaultParameterValues['Write-IrrationalLog:projectName'],
                $global:PSDefaultParameterValues['Write-IrrationalLog:outputtype'] 
            Join-Path $path $dest
        }
    }
    
    if( $psBoundParameters['PassThru'] ){

        [pscustomobject][ordered]@{
            ProjectName = $projectName
            Path        = $outputPath
            Parent      = Join-Path $path $global:PSDefaultParameterValues['Write-IrrationalLog:projectName']
            LogType     = $pscmdlet.ParameterSetName
            Defaults    = $global:PSDefaultParameterValues.getEnumerator().where{$_.name -like "Write-IrrationalLog:*"} | 
                            ConvertTo-Json -WarningAction 'silentlyContinue'
        }
    }
}

function Write-Log {

    <#
    .SYNOPSIS
        This function will send a standardized, structured output message for logs both to the pipeline and saved to a file

    .DESCRIPTION
        This function will send a standardized, structured output message for logs both to the pipeline and saved to a file. This function is intended to provide
        a complex solution to what is typically thought of as a simple problem, by making logs easier to digest, write and manipulate. This is primarily written
        with the interest of being used within a script so that a developer can focus writing code while having a reliable and structured method for organizing
        logs.

    .PARAMETER ProjectName
        The ProjectName can be used when organizing your logs. The ProjectName will organize all logs within a subfolder and name all logs according to this parameter

        Default: Logs

    .PARAMETER Collection
        The collection parameter can be used to output a specific set of log enteries to a new set of logs. 

        The intended use is to allow a new log for changes/modifications or errors without some of the additional noise from a standard log

    .PARAMETER Title
        The title parameter is added to the displayed log entry and intended to help organize logs of a specific type

        Default: GENERAL

    .PARAMETER Group
        Using the Group parameter is optional but provides an additional layer of organizing logging. This is particularly helpful when looping through objects.

        The group option accepts mutliple [String] inputs and can be used to organize output through multiple nested loops

    .PARAMETER Attachment
        The attachment parameter is used to store an object directly to the log message. This is particularly useful when further manipulation of the log output
        object is required

    .PARAMETER SaveAttachment
        When used, this parameter will create a new folder containing a json output of the specified log output including any attached objects

    .PARAMETER TimeFormat
        This can be used to specify the date as a ISO 8601 datetime string(standard)[default] or as an epoch time string

    .PARAMETER Message
        This is the main message which will be included in the log

        Mandatory: True

    .PARAMETER Severity
        Severity can be used to highlight specific log entries to more easily identify problems or potential issues

        Default: INFO

    .PARAMETER DisplaySeverityLevel
        This can be used to hide a specific level of messages. Default setting will display all messages marked as INFO or higher while DEBUG messages are hidden.

        When set even though messages are not displayed, all log info will still be written to a log file

    .PARAMETER LogVariable
        This will save the entire log object and any attachments included in that output to a variable. This is a global variable which will persist throughout 
        the current session

    .PARAMETER Source
        This can be used to identify the source of the log or the script where the error occurred

    .PARAMETER Path
        This is the output location where the log will be saved

        Default: ${ENV:TEMP}

    .PARAMETER OutputType
        This will specify the output type which will be generated for each log entry
        Options include:
            + csv:  A standard csv text file
            + log(DEFAULT) = this will generate a file which can be imported to ccmtrace log reader (sccm). This is ideal for shorter,simpler logs but data cannot 
                be reimported as an object when this format is used

    .PARAMETER GenerateEvent
        When used, this will generate a new Windows EventLog entry. The source type will use the ProjectName parameter.

        If the source type is new, this script must be run as an administrator to generate the new source type.

    .PARAMETER EnableLogRotation
        When enabled, this will allow the use of configuring the maximum log size and will rotate logs between output files. Files will
        no longer be date stamped when output

    .PARAMETER LogSizeMB
        When log rotation has been enabled, this is the maximum allowable log size in MB before the file will rotate

    .PARAMETER RotationLogCount
        When log rotation has been enabled, this is the maximum number of archived log files before the files are purged

    .PARAMETER PassThru
        This will send the entire log object to the pipeline

    .INPUTS
        [System.String]

    .OUTPUTS
        [System.Information]

        By default, a log entry will only generate information output which will sent to the pipeline. If using the -PassThru switch, an object of type 
        [IrrationalLog] will be sent to the pipeline

    .EXAMPLE
        PS> Write-IrrationalLog "test message" -OutputType csv

            [2022-05-01 12:00:15][INFO ][GENERAL   ][test message]

        This example shows the output stream which has been formatted as an information block. Log data will always be written to disk (in this case as csv):
            "2022-05-01 12:00:15","Info","GENERAL","test message"

    .NOTES
        All new entries should append new entries to existing log files if possible. The only time that entries are deleted is when the rotation file count limit 
        is reached
    #>

    [cmdletbinding( DefaultParameterSetName = 'DatedLogs' )]

    param(
        [Parameter( 
            Position = 0,
            ParameterSetName = 'DatedLogs',
            Mandatory = $true,
            HelpMessage = 'Please enter any text which should be included as a log entry' )]
        [Parameter( 
            Position = 0,
            ParameterSetName = 'RotationLog',
            Mandatory = $true,
            HelpMessage = 'Please enter any text which should be included as a log entry' )]
        [String] $Message,

        # Organizational Parameters
        [Parameter( ParameterSetName = 'DatedLogs' )]
        [Parameter( ParameterSetName = 'RotationLog' )]
        [String] $Title = 'GENERAL',

        [Parameter()]
        [String[]] $Group,

        [Parameter( ParameterSetName = 'DatedLogs' )]
        [Parameter( ParameterSetName = 'RotationLog' )]
        [String] $ProjectName = 'Logs',

        [Parameter()]
        [String[]] $Collection,

        [Parameter()]
        [ValidateSet('csv','log','txt')]
        [String] $OutputType = 'log',

        [Parameter()]
        [ValidateSet('EMERGENCY','ALERT','CRIT','ERROR','WARN','NOTICE','INFO','DEBUG')]
        [String] $Severity = 'Info',

        [Parameter()]
        [ValidateSet('EMERGENCY','ALERT','CRIT','ERROR','WARN','NOTICE','INFO','DEBUG')]
        [String] $DisplaySeverityLevel = 'Info',

        [Parameter()]
        [ValidateSet('EMERGENCY','ALERT','CRIT','ERROR','WARN','NOTICE','INFO','DEBUG')]
        [String] $GenerateErrorOn,

        [Parameter( ValueFromPipeline )]
        [PSObject[]] $Attachment,

        [Parameter()]
        [Switch] $SaveAttachment,

        [Parameter()]
        [String] $LogVariable,

        [Parameter()]
        [String] $Source = (
            ( $myinvocation.scriptName | Split-Path -Leaf -ErrorAction Ignore ) + ':' + $myInvocation.scriptLineNumber),

        [Parameter()]
        [ValidateScript({ Test-Path $_ })]
        [String] $Path = "${env:TEMP}",

        [Parameter()]
        [Alias('Session')]
        [PSObject] $ComputerName,

        [Parameter()]
        [Switch] $GenerateEvent = $false,

        [Parameter( ParameterSetName = 'RotationLog' )]
        [Switch] $EnableLogRotation = $false,

        [Parameter( ParameterSetName = 'RotationLog' )]
        [ValidateRange(1,5000)]
        [Int] $LogSizeMB = 200,

        [Parameter( ParameterSetName = 'RotationLog' )]
        [ValidateRange(1,20)]
        [Int] $RotationLogCount = 5,

        [Parameter()]
        [ValidateSet('epoch','standard')]
        [String] $TimeFormat = 'standard',

        [Parameter()]
        [Switch] $PassThru = $false
    )

    BEGIN{

        $code = {

            $outputFilePath = SetOutputPath $path $collection $projectName $outputType $enableLogRotation
            if( $PSBoundParameters['enableLogRotation'] ){ 

                UpdateRotationLog $outputFilePath $rotationLogCount $LogSizeMB 
            }

            # This section is used for a quick text replacement for standar 
            switch -regex ( $message ){

                '^\${{\s?LINEBREAK\s?}}$'   { $message = '-' * 120 }
            }

            # First we can determine any log settings based on severity
            $logSetting = [LogSetting]::New( $severity )

            # Now we can instantiate the log output object
            $output = [RationalLog]::New( 
                $timeFormat, 
                $projectName, 
                $title, 
                $group, 
                $collection, 
                $severity, 
                $message, 
                $logSetting, 
                $attachment, 
                $source 
            )

            # Next we format our console output string
            $outMessage = FormatOutputString $output

            # Log settings are then injected into host display output depending on the version used and sent back to the host
            $hostMsg = FormatHostOutput $outMessage $output

            # Passes the info back to the pipeline as an object
            if( $psBoundParameters['passThru'] ){ $output }

            # Adds the output as a variable - if it does not exist a new one is created - this is a global scope var
            if( $psBoundParameters['logVariable'] ){ SetLogVar $output $logVariable }

            # Finally, we can output the log data to the pipeline
            $debug = "Display Option: {0}({1})" -f $displaySeverityLevel,[int][severityMap]::($displaySeverityLevel.toUpper())
            Write-Debug $debug

            $msgDebug = "Message Severity: {0}({1})" -f $Severity,[int][severityMap]::($severity.toUpper()) 
            Write-Debug $msgDebug

            if( [int][SeverityMap]::($displaySeverityLevel.toUpper()) -ge [int][SeverityMap]::($severity.toUpper()) ){

                Write-Information $hostmsg -InformationAction Continue
            }

            # And now we can generates the final file output
            Write-Debug "OutputType: '$outputtype' :: OutputPath: '$($outputFilePath.path -join ',')'"
            OutputLogFile $outputType $outputFilePath $hostMsg $output
            Write-Verbose "Log saved to '$($output.path -join ', ')'"

            # This option will generate a separate group of logs contains the json output of a particular attachment
            if( $psBoundParameters['saveAttachment'] ){ SaveAttachment $outputFilePath $outMessage }

            # Generates an error message when the severity level is higher than the chosen option
            if( $psBoundParameters['GenerateErrorOn'] -AND 
                [int][SeverityMap]::($generateErrorOn.toUpper) -ge [int][SeverityMap]::($severity.toUpper()) ){

                Write-Error -Message $message
            }

            # Used to genereate an Event to the Application log on the log system
            if( $psBoundParameters['GenerateEvent'] ){ NewEventLogEntry $output }
        }

        # Imports the function to a remote session
        if( $psBoundParameters['ComputerName'] ){

            switch( $computerName ){
    
                { $_ -is [System.Management.Automation.Runspaces.PSSession] }  {
    
                    $verbose = "Existing session {0}({1}) will be used" -f $computername.computerName,$computername.instanceId
                    Write-Verbose $verbose
                    Invoke-Command -Session $computerName -ScriptBlock ${function:Write-Log}
                }

                default {

                    Write-Verbose "Attempting to connect directly to the host $computerName"
                    Invoke-Command -ComputerName ([string]$computerName) -ScriptBlock ${function:Write-Log}
                }
            }
        }
    }

    PROCESS{

        # This will allow the function to be executed remotely via remote function invocation
        if( $psBoundParameters['ComputerName'] ){

            switch( $computerName ){
    
                { $_ -is [System.Management.Automation.Runspaces.PSSession] }  {
    
                    Write-Verbose ( "Existing session {0}({1}) will be used" -f $session.computerName,$session.instanceId )
                    Invoke-Command -Session $computerName -ScriptBlock 
                }
                default {

                    Write-Verbose ( "Creating new session to $($computerName)" )
                    Invoke-Command -ComputerName $computerName -ScriptBlock
                }
            }
        }
        else{

            Invoke-Command -ScriptBlock $code
        }
    }
}

# Export Module Members
Export-ModuleMember -Function Write-Log,Set-Log

# Configure Alias Commands for Export
New-Alias -Name New-Log -Value Write-Log
Export-ModuleMember -Alias New-Log

New-Alias -Name 'log' -Value Write-Log
Export-ModuleMember -Alias log
