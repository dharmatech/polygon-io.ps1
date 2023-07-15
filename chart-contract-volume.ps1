
Param($underlying_ticker, $expiration_date, $strike_price, $contract_type, $date)

$api_key = $POLYGON_IO_API_KEY

# ----------------------------------------------------------------------
function unix-milliseconds-to-string ()
{
    param ([Parameter(Mandatory = $true, ValueFromPipeline = $true)]$val)

    [System.DateTimeOffset]::FromUnixTimeMilliseconds($val).LocalDateTime.ToString('yyyy-MM-dd HH:mm')
}

function options-ticker ($underlying, $expiration, [ValidateSet('call', 'put', 'C', 'P')] $type, $strike)
{
    if     ($type -eq 'call') { $type = 'C' }
    elseif ($type -eq 'put')  { $type = 'P' }

    'O:{0}{1}{2}{3}' -f $underlying, (Get-Date $expiration -Format 'yyMMdd'), $type, ($strike * 1000).ToString().PadLeft(8,'0')
}

function options-contract ($ticker)
{
    $result = Invoke-RestMethod "https://api.polygon.io/v3/reference/options/contracts/$($ticker)?apiKey=$api_key"

    $result.results
}

$field_timestamp_alt = @{ Label = 'timestamp'; Expression = { $_.t | unix-milliseconds-to-string } }
# ----------------------------------------------------------------------
$ticker = options-ticker $underlying_ticker $expiration_date $contract_type $strike_price

$contract = options-contract $ticker

$result_candles = Invoke-RestMethod "https://api.polygon.io/v2/aggs/ticker/$($contract.ticker)/range/5/minute/$($date)/$($date)?adjusted=true&sort=asc&limit=50000&apiKey=$api_key"

$result_candles.results | ft *, $field_timestamp_alt
# ----------------------------------------------------------------------
$json = @{
    chart = @{
        type = 'bar'
        data = @{
            labels = $result_candles.results | Select-Object $field_timestamp_alt | % timestamp
            datasets = @(
                @{ label = 'volume';        data = $result_candles.results | % v }
                @{ label = 'average price'; data = $result_candles.results | % vw; yAxisID = 'Y2'; type = 'line'; fill = $false }
            )
        }
        options = @{
            title = @{ 
                display = $true
                text = @(
                    ('Contract volume {0} {1} {2}' -f $contract.underlying_ticker, $contract.expiration_date, $contract.strike_price)
                    ) 
            }
            scales = @{ 
                
                yAxes = @(
                    @{ id = 'Y1'; position = 'left';  display = $true }
                    @{ id = 'Y2'; position = 'right'; display = $true }
                )

            }
        }
    }
} | ConvertTo-Json -Depth 100

$result = Invoke-RestMethod -Method Post -Uri 'https://quickchart.io/chart/create' -Body $json -ContentType 'application/json'

$id = ([System.Uri] $result.url).Segments[-1]

Start-Process ('https://quickchart.io/chart-maker/view/{0}' -f $id)
# ----------------------------------------------------------------------

