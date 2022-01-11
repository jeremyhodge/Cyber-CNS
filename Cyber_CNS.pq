section Cyber_CNS;

// Macros
GetSchemaForEntity = (entity as text) as type => try SchemaTable{[Entity=entity]}[SchemaTable] otherwise error "Couldn't find entity: '" & entity & "'";
Extension.LoadFunction = (name as text) =>
    let
        binary = Extension.Contents(name),
        asText = Text.FromBinary(binary)
    in
        Expression.Evaluate(asText, #shared);

Table.GenerateByPage = try Extension.LoadFunction("Table.GenerateByPage.pqm") otherwise error "Unable to load GenerateByPage extension";
Table.ToNavigationTable = try Extension.LoadFunction("Table.ToNavigationTable.pqm") otherwise error "Unable to load ToNavigationTable extension";
Table.ChangeType = try Extension.LoadFunction("Table.ChangeType.pqm") otherwise error "Unable to load ChangeType extension";

Diagnostics = try Extension.LoadFunction("Diagnostics.pqm") otherwise error "Unable to load Diagnostics extension";
Diagnostics.LogValue = Diagnostics[LogValue];
Diagnostics.LogFailure = Diagnostics[LogFailure];
Diagnostics.WrapHandlers = Diagnostics[WrapHandlers];

// Load API Information
Endpoints = try Extension.LoadFunction("Endpoints.pqm") otherwise error "Unable to load API Endpoints";
SchemaTable = try Extension.LoadFunction("Schemas.pqm") otherwise error "Unable to load API Schema";

// API DataSource Definition
[DataSource.Kind="Cyber_CNS", Publish="Cyber_CNS.Publish"]
shared Cyber_CNS.Contents = Value.ReplaceType(Cyber_CNS.NavTable, type function (ServiceURI as Uri.Type) as any);

//TODO: Load label values from resource file
Cyber_CNS = [
    Authentication = [
        UsernamePassword = [
            UsernameLabel = "Clent ID",
            PasswordLabel = "Client Secret",
            Label = "Client ID & Secret"
        ]
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

Cyber_CNS.NavTable = (_ServiceURI as text) as table =>
    let 
        accessToken = Cyber_CNS.doAuthentication(_ServiceURI),
        Source = Endpoints,                                                                                                                                    
        withData = Table.AddColumn(Source, "Data", each Cyber_CNS.View([Endpoint], [Schema], _ServiceURI, accessToken), Table.Type),
        withoutEndpoint = Table.RemoveColumns(withData, { "Endpoint", "Schema" }),
        withItemKind = Table.AddColumn(withoutEndpoint, "ItemKind", each "Table", type text),
        withItemName = Table.AddColumn(withItemKind, "ItemName", each "Table", type text),
        withIsLeaf = Table.AddColumn(withItemName, "IsLeaf", each true, type logical),
        navTable = Table.ToNavigationTable(withIsLeaf, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable;

Cyber_CNS.Publish = [
    Beta = true,
    Category = "MSP Power Platform Project",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://www.cybercns.com/",
    SourceImage = Cyber_CNS.Icons,
    SourceTypeImage = Cyber_CNS.Icons
];

Cyber_CNS.Icons = [
    Icon16 = { Extension.Contents("Cyber_CNS16.png"), Extension.Contents("Cyber_CNS20.png"), Extension.Contents("Cyber_CNS24.png"), Extension.Contents("Cyber_CNS32.png") },
    Icon32 = { Extension.Contents("Cyber_CNS32.png"), Extension.Contents("Cyber_CNS40.png"), Extension.Contents("Cyber_CNS48.png"), Extension.Contents("Cyber_CNS64.png") }
];

Cyber_CNS.View = (baseUrl as text, entity as text, _ServiceURI, accessToken) as table =>
    let
        View = (state as record) => Table.View(null, Diagnostics.WrapHandlers([
            GetType = () => CalculateSchema(state),

            GetRows = () => 
                let
                    finalSchema = CalculateSchema(state),
                    finalUrl = CalculateUrl(state),

                    result = Cyber_CNS.GetPagedTable(finalUrl, finalSchema, accessToken),
                    appliedType = Table.ChangeType(result, finalSchema)
                in
                    appliedType,

            GetRowCount = () as number =>
                if (Record.FieldCount(Record.RemoveFields(state, {"Url", "Entity", "Schema"}, MissingField.Ignore)) > 0) then
                    ...
                else
                    let
                        newState = state & [ RowCountOnly = true ],
                        finalUrl = CalculateUrl(newState),
                        value = 0, //TripPin.Scalar(finalUrl),
                        converted = Number.FromText(value)
                    in
                        converted,

            OnTake = (count as number) =>
                let 
                    newState = state & [ Top = count ]
                in
                    @View(newState),

            OnSkip = (count as number) =>
                let
                    newState = state & [ Skip = count ]
                in
                    @View(newState),

            OnSelectColumns = (columns as list) =>
                let
                    currentSchema = CalculateSchema(state),
                    rowRecordType = Type.RecordFields(Type.TableRow(currentSchema)),
                    existingColumns = Record.FieldNames(rowRecordType),
                    columnsToRemove = List.Difference(existingColumns, columns),
                    updatedColumns = Record.RemoveFields(rowRecordType, columnsToRemove),
                    newSchema = type table (Type.ForRecord(updatedColumns, false))
                in
                    @View(state & 
                        [ 
                            SelectColumns = columns,
                            Schema = newSchema
                        ]
                    ),

            OnSort = (order as list) =>
                let
                    sorting = List.Transform(order, (o) => 
                        let
                            column = o[Name],
                            order = o[Order],
                            orderText = if (order = Order.Ascending) then "asc" else "desc"
                        in
                            "{" & """" & column & """:{""order"":""" & orderText & """}}"
                    ),
                    orderBy = "[" & Text.Combine(sorting, ", ") & "]"
                in
                    @View(state & [ OrderBy = orderBy ]),

            CalculateSchema = (state) as type =>
                if (state[Schema]? = null) then
                    GetSchemaForEntity(entity)
                else
                    state[Schema],

            CalculateUrl = (state) as text => 
/*
                let
                    _params = Unitrends_MSP.GetParamsForEntity(state[Entity]),
                    params = if (_params = "") then null else _params,
                    sort = if (state[OrderBy]? = null) then null else "sort=" & state[OrderBy],
                    fields = if (state[SelectColumns]? = null) then null else "fields=" & Text.Combine(state[SelectColumns], ","),
                    _queryString = Text.Combine(List.RemoveNulls({ params, sort, fields }), "&"),
                    queryString = if (_queryString <> "") then "?" & _queryString else "",
                    _urlWithEntity = Uri.Combine(state[Url], Unitrends_MSP.GetEndpointForEntity(state[Entity])) & queryString,
                    urlWithEntity = Diagnostics.LogValue("Unitrends_MSP.CalculateUrl", _urlWithEntity)
                in
                    urlWithEntity
*/                                
                let
                    urlWithEntity = Uri.Combine(state[Url], state[Entity])
                in
                    urlWithEntity
        ]))
    in
        View([Url = baseUrl, Entity = entity]);

Cyber_CNS.GetEntity = (endpoint as text, entity as text, _ServiceURI as text, accessToken as text) as table =>
    let
        fullUrl = Uri.Combine(_ServiceURI, endpoint),
        schema = GetSchemaForEntity(entity),
        result = Cyber_CNS.GetPagedTable(fullUrl, schema, accessToken),
        applySchema = Table.ChangeType(result, schema)
    in
        applySchema;

Cyber_CNS.GetPagedTable = (endpoint as text, schema as type, accessToken as text) => Table.GenerateByPage((previous) =>
    let
        pPage =  if (previous <> null) then Number.From(Value.Metadata(previous)[page]) else 0,
        pCount = if (previous <> null) then Number.From(Value.Metadata(previous)[count]) else 5000,
        pTotal = if (previous <> null) then Number.From(Value.Metadata(previous)[total]) else 5000,
        urlToUse = (if Text.Contains(endpoint, "?") then endpoint & "&" else endpoint & "/?") & "skip=" & Text.From(pCount * pPage) & "&limit=" & Text.From(pCount),
        current = if (pPage * pCount) >= pTotal then null else Cyber_CNS.GetPage(urlToUse, schema, accessToken),
        page = pPage + 1,
        total = if (current <> null) then Value.Metadata(current)[total] else null,
        count = if (current <> null) then Value.Metadata(current)[count] else null
    in
        current meta [page=page, total=total, count=count]
);

Cyber_CNS.GetPage = (endpoint as text, schema as type, accessToken as text) as table =>
    let
        webDoc = Web.Contents(endpoint, [ Headers = [ #"User-Agent" = "Cyber_CNS-Custom-Connector/1.0.0", #"Accept" = "application/json", Cookie = accessToken ], ManualCredentials = true ]),
        body = Json.Document(webDoc),
        total = if (Value.Type(body) = List.Type) then 0 else body[total],
        count = if (Value.Type(body) = List.Type) then 0 else body[count],
        data =
            if (schema <> null) then 
                if (Value.Type(body) = List.Type) then
                    let
                        asTable = Table.FromList(body, Splitter.SplitByNothing(), {"Column1"}),
                        fields = Record.FieldNames(Type.RecordFields(Type.TableRow(schema))),
                        expanded = Table.ExpandRecordColumn(asTable, "Column1", fields)  
                    in
                        expanded
                else
                    Table.FromRecords(body[data])
            else
                let
                    asTable = Table.FromList(body[data], Splitter.SplitByNothing(), {"Column1"}),
                    fields = Record.FieldNames(Type.RecordFields(Type.TableRow(schema))),
                    expanded = Table.ExpandRecordColumn(asTable, fields)
                in
                    expanded
    in
        data meta [total=total, count=count];

Cyber_CNS.doAuthentication = (_ServiceURI as text) =>
    let
        AuthenticationEndpoint = "/api/login",
        WebContent = Web.Contents(Uri.Combine(_ServiceURI, AuthenticationEndpoint), [
            Headers = [
                #"Content-type" = "application/x-www-form-urlencoded",
                #"Authorization" = "Basic " & Binary.ToText(Text.ToBinary(Extension.CurrentCredential()[Username] & ":" & Extension.CurrentCredential()[Password], BinaryEncoding.Base64)),
                #"User-Agent" = "Cyber_CNS-Custom-Connector/1.0.0", 
                #"Accept" = "*/*",
                #"Cache-Control" = "no-cache"
            ],
            ManualCredentials = true
        ]),
        cookie = Value.Metadata(WebContent)[Headers][#"Set-Cookie"]
    in
        cookie;
