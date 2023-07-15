
Param($symbol, $date, [switch]$puts_on_bottom)

$api_key = $POLYGON_IO_API_KEY

function unix-milliseconds-to-string ()
{
    param ([Parameter(Mandatory = $true, ValueFromPipeline = $true)]$val)

    [System.DateTimeOffset]::FromUnixTimeMilliseconds($val).LocalDateTime.ToString('yyyy-MM-dd HH:mm')
}

# ----------------------------------------------------------------------
# query for all contracts
# ----------------------------------------------------------------------

function get-contracts ($symbol)
{
    Write-Host 'get-contracts' -ForegroundColor Yellow

    $contracts = @()

    $result_contracts = Invoke-RestMethod "https://api.polygon.io/v3/reference/options/contracts?underlying_ticker=$symbol&as_of=$date&limit=1000&apiKey=$api_key"

    $contracts += $result_contracts.results

    while ($result_contracts.next_url -ne $null)
    {
        Write-Host '.' -ForegroundColor Yellow

        $result_contracts = Invoke-RestMethod $result_contracts.next_url -Headers @{ "Authorization" = "Bearer $api_key" }
        
        $contracts += $result_contracts.results
    }

    $contracts
}

$contracts = get-contracts $symbol

# ----------------------------------------------------------------------
# get candles for each contract
# ----------------------------------------------------------------------

Write-Host 'getting candles for each contract' -ForegroundColor Yellow

foreach ($contract in $contracts) 
{
    Write-Host $contract.ticker -ForegroundColor Yellow
    # $ticker = $contract.ticker

    # $result_trades = Invoke-RestMethod "https://api.polygon.io/v3/trades/$($ticker)?timestamp=2023-07-14&limit=1000&apiKey=$api_key"

    $result_candles = Invoke-RestMethod "https://api.polygon.io/v2/aggs/ticker/$($contract.ticker)/range/5/minute/$($date)/$($date)?adjusted=true&limit=1000&apiKey=$api_key"   
    
    $contract | Add-Member -MemberType NoteProperty -Name candles -Value $result_candles.results -Force
}

# ----------------------------------------------------------------------
# all candles
# ----------------------------------------------------------------------

Write-Host 'processing candles' -ForegroundColor Yellow

# add contract_type to each candle
# add expiration    to each candle

foreach ($contract in $contracts)
{
    Write-Host ('{0}' -f $contract.ticker) -ForegroundColor Yellow

    foreach ($candle in $contract.candles)
    {
        Write-Host '.' -ForegroundColor Yellow -NoNewline
        $candle | Add-Member -MemberType NoteProperty -Name contract_type   -Value $contract.contract_type   -Force
        $candle | Add-Member -MemberType NoteProperty -Name expiration_date -Value $contract.expiration_date -Force

        $candle | Add-Member -MemberType NoteProperty -Name date -Value ($candle.t | unix-milliseconds-to-string) -Force
    }
}

$all_candles = $contracts | ForEach-Object { $_.candles }

$all_candles = $all_candles | ? { $_ -ne $null }

# ----------------------------------------------------------------------
# chart volume for all contracts
# ----------------------------------------------------------------------

Write-Host 'Generating chart' -ForegroundColor Yellow

$labels = $all_candles | % date | Sort-Object -Unique

# ----------
# calls
# ----------
$groups = $all_candles | ? contract_type -EQ call | Group-Object date | Sort-Object Name

$volume_table = $groups | Select-Object Name, @{ Label = 'volume'; Expression = { $_.Group | Measure-Object v -Sum | % Sum } }

$call_volume = $labels | ForEach-Object { $volume_table | ? Name -EQ $_ | % volume }
# ----------
# puts
# ----------
$groups = $all_candles | ? contract_type -EQ put | Group-Object date | Sort-Object Name

$volume_table = $groups | Select-Object Name, @{ Label = 'volume'; Expression = { $_.Group | Measure-Object v -Sum | % Sum } }

$put_volume = $labels | ForEach-Object { $volume_table | ? Name -EQ $_ | % volume }

$toggle = if ($puts_on_bottom.IsPresent) { -1 } else { 1 }

$put_volume = $put_volume | ForEach-Object { $toggle * $_ }

$json = @{
    chart = @{
        type = 'bar'
        data = @{
            labels = $labels
            datasets = @(
                @{ label = 'call volume';        data = $call_volume }
                @{ label = 'put volume';        data = $put_volume }
            )
        }
        options = @{
            title = @{ 
                display = $true
                text = @(
                    ('{0}' -f $contracts[0].underlying_ticker)
                    ) 
            }
            scales = @{ 

                xAxes = @( @{ stacked = $true } ) 
                yAxes = @( @{ stacked = $true } )                 
                
                # yAxes = @(
                #     @{ id = 'Y1'; position = 'left';  display = $true }
                #     @{ id = 'Y2'; position = 'right'; display = $true }
                # )

            }
        }
    }
} | ConvertTo-Json -Depth 100

$result = Invoke-RestMethod -Method Post -Uri 'https://quickchart.io/chart/create' -Body $json -ContentType 'application/json'

$id = ([System.Uri] $result.url).Segments[-1]

Start-Process ('https://quickchart.io/chart-maker/view/{0}' -f $id)
# ----------------------------------------------------------------------
exit
# ----------------------------------------------------------------------
.\chart-day-volume.ps1 -symbol IWM -date 2023-07-14

.\chart-day-volume.ps1 -symbol DM -date 2023-07-14

. .\chart-day-volume.ps1 -symbol DM -date 2023-07-14 -puts_on_bottom