# App Insights Functions

## valid_startup_requests

```kql
requests
| where resultCode in (```208```, ```201```)
| where operation_Name in (```startup```)
```

## container_group_extended

```kql
let pattern = @"INFORMATION: Container group '([\w-_]+)' exists: ([TF][ra][ul][es]e?)";
traces
 | where message matches regex pattern
 | where operation_Name == "startup"
 | extend container_name = extract(pattern, 1, message)
 | extend container_existed = tobool(extract(pattern, 2, message))
```

## valid_startup_requests_extended

```kql
valid_startup_requests
| join kind = inner (container_group_extended) on $left.operation_Id == $right.operation_Id
| project timestamp, operation_Id, operation_Name, container_name, container_existed, duration, performanceBucket
```
