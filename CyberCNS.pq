section CyberCNS;

//TODO: Load label values from resource file
CyberCNS = [
    TestConnection = (dataSourcePath) => { "CyberCNS.Contents" },    
    Authentication = [
        UsernamePassword = [
            UsernameLabel = "Clent ID",
            PasswordLabel = "Client Secret",
            Label = "Client ID & Secret"
        ]
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

CyberCNS.Publish = [
    Beta = true,
    Category = "Online Services",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://www.cybercns.com/",
    SourceImage = CyberCNS.Icons,
    SourceTypeImage = CyberCNS.Icons
];

CyberCNS.Icons = [
    Icon16 = { Extension.Contents("CyberCNS16.png"), Extension.Contents("CyberCNS20.png"), Extension.Contents("CyberCNS24.png"), Extension.Contents("CyberCNS32.png") },
    Icon32 = { Extension.Contents("CyberCNS32.png"), Extension.Contents("CyberCNS40.png"), Extension.Contents("CyberCNS48.png"), Extension.Contents("CyberCNS64.png") }
];

//
// Implementation
//
[DataSource.Kind="CyberCNS", Publish="CyberCNS.Publish"]
shared CyberCNS.Contents = Value.ReplaceType(CyberCNS.NavTable, type function (ServiceURI as Uri.Type) as any);

// Load API Information
CyberCNS.Endpoints = Extension.LoadFunction("Endpoints.pqm");
CyberCNS.Schema = Extension.LoadFunction("Schemas.pqm");

CyberCNS.NavTable = (_ServiceURI as text) as table =>
    let 
        accessToken = CyberCNS.doAuthentication(_ServiceURI),
        Source = CyberCNS.Endpoints,                                                                                                                                    
        withData = Table.AddColumn(Source, "Data", each CyberCNS.View(Uri.Combine(_ServiceURI, [Endpoint]), [Schema], accessToken), Table.Type),
        withoutEndpoint = Table.RemoveColumns(withData, { "Endpoint", "Schema", "Params", "AllowPaging", "AltDataPath" }),
        withItemKind = Table.AddColumn(withoutEndpoint, "ItemKind", each "Table", type text),
        withItemName = Table.AddColumn(withItemKind, "ItemName", each "Table", type text),
        withIsLeaf = Table.AddColumn(withItemName, "IsLeaf", each true, type logical),
        navTable = Table.ToNavigationTable(withIsLeaf, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable;   //{[Name="Companies"]}[Data];

CyberCNS.View = (baseUrl as text, entity as text, accessToken as text) as table =>
    let
        View = (state as record) => Table.View(null, Diagnostics.WrapHandlers([
            GetType = () => CalculateSchema(state),

            GetRows = () => 
                let
                    finalSchema = CalculateSchema(state),
                    finalUrl = CalculateUrl(state),
                    allowPaging = (CyberCNS.GetAllowPagingForEntity(state[Entity]) = "true"),

                    result = CyberCNS.GetPagedTable(finalUrl, finalSchema, accessToken, allowPaging, (if (state[Top]? <> null) then state[Top] else 0), (if (state[Skip]? <> null) then state[Skip] else 0) ),
                    appliedType = Table.ChangeType(result, finalSchema)
                in
                    appliedType,
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
                    CyberCNS.GetSchemaForEntity(entity)
                else
                    state[Schema],

            CalculateUrl = (state) as text => 
                let
                    _params = CyberCNS.GetParamsForEntity(state[Entity]),
                    params = if (_params = "") then null else _params,
                    sort = if (state[OrderBy]? = null) then null else "sort=" & state[OrderBy],
                    fields = if (state[SelectColumns]? = null) then null else "fields=" & Text.Combine(state[SelectColumns], ","),
                    _queryString = Text.Combine(List.RemoveNulls({ params, sort }), "&"),   // , fields
                    queryString = if (_queryString <> "") then "?" & _queryString else "",
                    urlWithEntity = Uri.Combine(state[Url], CyberCNS.GetEndpointForEntity(state[Entity])) & queryString
                in
                    urlWithEntity
        ]))
    in
        View([Url = baseUrl, Entity = entity]);

CyberCNS.GetPagedTable = (endpoint as text, schema as type, accessToken as text, allowPaging as logical, maxCount as number, offSet as number) => Table.GenerateByPage((previous) =>
        if (allowPaging = "false" and previous <> null) then
            null
        else
            let
                _pCount = if (previous <> null) then Number.From(Value.Metadata(previous)[count]) else 5000,
                pCount = if (maxCount < _pCount) and (maxCount > 0) then maxCount else _pCount,
                pPage = if (previous <> null) then Number.From(Value.Metadata(previous)[page]) else if (offSet <> 0) then Number.IntegerDivide(offSet, pCount) + (if (Number.Mod(offSet, pCount) > 0) then 1 else 0) else 0,
                pTotal = if (previous <> null) then Number.From(Value.Metadata(previous)[total]) else 999999,
                
                _current = if 
                    pTotal = 0 or  // no records returned in previous call
                    (pPage * pCount) >= pTotal or  // previous call returned all the records there are to return
                    ((pPage * pCount) >= maxCount and (maxCount > 0)) then   // previous call returned all or more than the number of records that was asked for
                        null
                    else
                        let
                            urlToUse = if (allowPaging) then
                                    (if Text.Contains(endpoint, "?") then endpoint & "&" else endpoint & "/?") & "skip=" & Text.From(pPage) & "&limit=" & Text.From(pCount)
                                else
                                    endpoint
                        in
                            CyberCNS.GetPage(urlToUse, schema, accessToken),

                page = pPage + 1,
                offsetCount = if (maxCount > 0) then maxCount - (pPage * pCount) else 0,
                current = if (_current <> null) and 
                                (page * pCount) > maxCount and
                                maxCount > 0 then
                            Table.RemoveRows(_current, offsetCount, Table.RowCount(_current) - offsetCount)
                            else
                            _current,

                total = if (current <> null) then Value.Metadata(_current)[total] else null,
                count = if (current <> null) then Value.Metadata(_current)[count] else null
            in
                current meta [ page=page, total=total, count=pCount ]
);

CyberCNS.GetPage = (endpoint as text, schema as type, accessToken as text) as table =>
    let
        webDoc = Web.Contents(endpoint, [ Headers = [ #"User-Agent" = "CyberCNS-Custom-Connector/1.0.0", #"Accept" = "application/json", Cookie = accessToken ], ManualCredentials = true ]),
        _body = Json.Document(webDoc),
        bodyType = Value.Type(_body),
        body = 
            if bodyType = type { any } then
                [ data = _body, count = List.Count(_body), total = List.Count(_body) ]
            else
                _body,

        
        total = if (bodyType = List.Type) then 0 else body[total],
        count = if (bodyType = List.Type) then 0 else body[count],
        data =
            if (schema = null) then 
                Diagnostics.LogFailure("Error converting response body. Are the records uniform?",
                    () => Table.FromRecords(body)
                )
            else
                let
                    asTable = Table.FromList(body[data], Splitter.SplitByNothing(), {"Column1"}),
                    fields = Record.FieldNames(Type.RecordFields(Type.TableRow(schema))),
                    expanded = Table.ExpandRecordColumn(asTable, "Column1", fields)
                in
                    expanded
    in
        data meta [total=total, count=count];

CyberCNS.doAuthentication = (_ServiceURI as text) =>
    let
        AuthenticationEndpoint = "/api/login",
        WebContent = Web.Contents(Uri.Combine(_ServiceURI, AuthenticationEndpoint), [
            Headers = [
                #"Content-type" = "application/x-www-form-urlencoded",
                #"Authorization" = "Basic " & Binary.ToText(Text.ToBinary(Extension.CurrentCredential()[Username] & ":" & Extension.CurrentCredential()[Password], BinaryEncoding.Base64)),
                #"User-Agent" = "CyberCNS-Custom-Connector/1.0.0", 
                #"Accept" = "*/*",
                #"Cache-Control" = "no-cache"
            ],
            ManualCredentials = true
        ]),
        cookie = Value.Metadata(WebContent)[Headers][#"Set-Cookie"]
    in
        cookie;


CyberCNS.GetSchemaForEntity = (entity as text) as type =>
    try
        CyberCNS.Schema{[Entity=entity]}[Type]
    otherwise 
        let 
            message = Text.Format("Couldn't find entity: '#{0}'", {entity})
        in
            Diagnostics.Trace(TraceLevel.Error, message, () => error message, true);

CyberCNS.GetEndpointForEntity = (entity as text) as text =>
    try
        CyberCNS.Endpoints{[Schema=entity]}[Endpoint]
    otherwise 
        let 
            message = Text.Format("Couldn't find entity: '#{0}'", {entity})
        in
            Diagnostics.Trace(TraceLevel.Error, message, () => error message, true);

CyberCNS.GetParamsForEntity = (entity as text) as text =>
    try
        CyberCNS.Endpoints{[Schema=entity]}[Params]
    otherwise 
        let 
            message = Text.Format("Couldn't find entity: '#{0}'", {entity})
        in
            Diagnostics.Trace(TraceLevel.Error, message, () => error message, true);

CyberCNS.GetAllowPagingForEntity = (entity as text) as text =>
    try
        CyberCNS.Endpoints{[Schema=entity]}[AllowPaging]
    otherwise  
        let 
            message = Text.Format("Couldn't find entity: '#{0}'", {entity})
        in
            Diagnostics.Trace(TraceLevel.Error, message, () => error message, true);


//***********************************************************************************************//
//
// Common Library Functions
//
//
Extension.LoadFunction = (name as text) =>
    try
        let        
            binary = Extension.Contents(name),
            asText = Text.FromBinary(binary)
        in
            Expression.Evaluate(asText, #shared)
    otherwise
        error "Unable to load external resource: " & name;

Table.GenerateByPage = Extension.LoadFunction("Table.GenerateByPage.pqm");
Table.ToNavigationTable = Extension.LoadFunction("Table.ToNavigationTable.pqm");
Table.ChangeType = Extension.LoadFunction("Table.ChangeType.pqm");

Diagnostics = Extension.LoadFunction("Diagnostics.pqm");
Diagnostics.LogValue = Diagnostics[LogValue];
Diagnostics.LogFailure = Diagnostics[LogFailure];
Diagnostics.WrapHandlers = Diagnostics[WrapHandlers];
