param(
    [int]$min = 30,
    [string]$port = "portNumber"
)

#Conexión a la base de datos:
$connectionString = "Server = ServerName; Database = DatabaseName; Integrated Security = True;"
$connection = New-Object System.Data.SqlClient.Sqlconnection
$connection.ConnectionString = $connectionString

$URL = "http:/localhost:$($port)/"

$listener = New-Object System.Net.HttpListener

$listener.Prefixes.Add($URL)
Write-Host "Starting Server" -ForegroundColor Yellow
$listener.Start()

if($listener.IsListening){
    Write-Host "Server is running on $($URL)" -ForegroundColor Blue
    Start-Process "http:/localhost:$port/URL_SubFolder"
}

function Get-SQLData{
    $jsonResults = $null
    try {
        Write-Host "Opening Connection..." -ForegroundColor Cyan
        $connection.Open();
        if($connection.State -eq "Open"){
            Write-Host "Opened" -ForegroundColor Green
        }
        $command = $connection.CreateCommand();
        $command.CommandText = "SELECT InformacionExtraida [RunLabelFilterInfold], [FilterName], [LabelName] FROM NombreDataBase"
        $result = $command.ExecuteReader();

        $results = @();
        while ($result.Read()){
            Write-Host $result[0];
            $row = New-Object PSObject
            for ($i = 0; $i -lt $result.FieldCount; $i++){
                $row | Add-Member -MemberType NoteProperty -Name $result.GetName($i) -Value $result.GetValue($i)
                $results += $row
            }
        }

        $jsonResults = $results | ConvertTo-JSON;
        Write-Host $jsonResults;
    }
    catch {
        Write-Host "Upsi, se ha producido un error!!" -ForegroundColor Tomato
    }
    finally {
        if($connection.State -eq "Open"){
            $connection.Close();
            Write-Host "Closing Connection" -ForegroundColor Magenta
            if($connection.State -eq "Close"){
                Write-Host "Closed" -ForegroundColor Green
            }
        }
    }
    return $jsonResults
}

function Read-Request{
    param($context)
    $request = $context.Request;
    $response = $context.Response;
    Write-Host "A new Call Received $($request.Url) $($request.UserHostAdress)" -ForegroundColor Blue

    $response.Headers.Add("Access-Control-Allow-Origin", "*");
    $response.Headers.Add("Access-Control-Allow-Methods", "GET", "POST");
    $response.Headers.Add("Access-Control-Allow-Headers", "Access-Control-Allow-Headers, Authorization, X-Requested-With");
    
    $totalTime = Measure-Command{
        $res = $null;
        switch ($request.HttpMethod){
            'GET'{
                if($request.RawUrl -eq "/URL_SubFolder"){
                    $response.Headers.Add("Content-Type", "text/html")
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes([System.IO.File]::ReadAllText("./FileName.extension"))
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length);
                    $response.StatusCode = 200;
                }else{
                    $response.Headers.Add("Content-Type", "application/json")
                    $myObject = @{
                        $information = "Server information..."
                    }
                    $res = $myObject | ConvertTo-JSON
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($res);
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length);
                    $response.StatusCode = 200;
                }
            }
            'POST'{
                $response.Headers.Add("Content-Type", "application/json")
                $theInput = New-Object IO.StreamReader $request.InputStream
                $data = $theInput.ReadToEnd() | ConvertFrom-JSON
                $res = Get-SQLData $data | ConvertTo-JSON -Depth 10
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($res);
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length);
                $response.StatusCode = 200;
            }
            Default{
                $response.StatusCode = 404;
            }
        }
        $response.OutputStream.Close();
    }
    $response.Close();
    Write-Host "Requested completed and Response sent in $($totalTime)s" -ForegroundColor Blue
}

try {
    $checker = $true
    while($checker){
        try {
            $asyncResult = $listener.BeginGetContext($null, $null);
            Write-Host "Waiting for a new call in the next $(60 * $min)s" -ForegroundColor Green
            if($asyncResult.AsyncWaitHandle.WaitOne((60000 * $min))){
                $context = $listener.EndGetContext($asyncResult);
                Read-Request $context;
                $asyncResult.AsyncWaitHandle.Close();
                $asyncResult.AsyncWaitHandle.Dispose();
            }else{
                Write-Host "No HTTP calls at the moment" -ForegroundColor Red;
                $checker = $false
                $asyncResult.AsyncWaitHandle.Close();
                $asyncResult.AsyncWaitHandle.Dispose();
            }
        }
        catch [System.Exception]{
            Write-Host "Error: $_"
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
    Write-Host "The server has stopped" -BackgroundColor Red;
}