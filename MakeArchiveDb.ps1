<# The fuction writes the data 
about the actions that was donne this script
to the Application event log. #>
function Write-AppEventLog 
{
    param($entryType, $errorMessage)
 
    $eventSource = "MakeArchiveDb"
    $eventID = 65432

    If ([System.Diagnostics.EventLog]::SourceExists($eventSource) -eq $False) {
       New-EventLog -LogName Application -Source $eventSource
    }

    Write-EventLog -LogName Application -EventID $eventID -EntryType $entryType -Source $eventSource -Message $errorMessage
}


<# The function reads and adds to the Params dictionary 
each line of the Content object which split by symbol '=' like a key and value. #>
function Get-DatabaseParameters
{
    param($content)

    $params = @{}
    foreach($line in $content) {
        $splitted = $line -split "="
        $params[$splitted[0]] = $splitted[1]
    }
    return $params
}


<# Permanently ends a session and closes the data connection between 
the 1C database in cluster and 1C client. #>
function Database-TerminateSession 
{
    param($params)
    
    try 
    {
        $connector = New-Object -ComObject V83.COMConnector
        $agent = $connector.ConnectAgent($params.Server)
        $clusters = $agent.GetClusters()
    
        foreach($cluster in $clusters) {
            $agent.Authenticate($cluster, $params.ClusterAdmin, $params.ClusterPassword)
		    $processes = $agent.GetWorkingProcesses($cluster)
        
            foreach($process in $processes) {
                $workingProcess = $connector.ConnectWorkingProcess($params.Server + ":" + $process.MainPort);
			    $workingProcess.AddAuthentication("", "");
			    $baseInfo = ""
			    $workingBases = $agent.GetInfoBases($cluster);
			          
                #Determine the required database.
                foreach($base in $workingBases) {
                    if ($base.Name -eq $params.BaseName) {
                        $baseInfo = $base
                        break
                    }
                }
            
                $seances = $agent.GetInfoBaseSessions($cluster, $baseInfo);			
            
                #Terminate all session, except for a background jobs.
                foreach($seance in $seances) {
                
                    if( $seance.AppID.ToLower() -eq "backgroundjob") {
                        continue
                    }
                
                    $agent.TerminateSession($cluster, $seance);
                }
         
            }
        }
        return @{Code = 0; Message = ""}
    } 
    catch 
    {
        return @{Code = 1; Message = $_.Exception.Message}
    }
}


<# The function make back up the database. #>
function BackUp-Database 
{
    param($params)

    [System.Threading.Thread]::Sleep([System.Int32]::Parse($params.WaitTimeInSeconds) * 1000)

    $now = [System.DateTime]::Now
    
    $arch_name = [System.String]::Format("{0:dd}{1:MM}{2:yyyy}_{3:HH}{4:mm}", $now, $now, $now, $now, $now)
    $full_arch_path = $params.ArchivePath + "\" + $arch_name + ".dt" 
    $path_to_base = $params.Server + "\" + $params.BaseName
    
    #Execute the command.
    & $params.PathTo1C8 'CONFIG', '/S', $path_to_base, '/N', $params.UserName, '/P', $params.UserPassword, '/DumpIB', $full_arch_path, '/DisableStartupMessages'
    
    $msg = "Script - back up database 1C: successfully completed."  	
    Write-AppEventLog ([System.Diagnostics.EventLogEntryType]::Information) $msg
}


function Main 
{
    param($content)

    $params = Get-DatabaseParameters $content
    $info = Database-TerminateSession $params
    
    if ($info.Code -eq 0) {
        BackUp-Database $params
    }
    else {
        $msg = "Script - back up database 1C: some wrong occurred." + 
           "`nCheck all parameters and registaration `"V83.COMConnector`" of component." +
           "`nError message: $info.Message"

	    Write-AppEventLog ([System.Diagnostics.EventLogEntryType]::Warning) $msg
    }
}


Main (Get-Content -path "C:\distr\scripts\srv.properties")
Main (Get-Content -path "C:\distr\scripts\srv_prettl_zup.properties")
