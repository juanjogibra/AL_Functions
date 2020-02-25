/*  Como crear Enums    */

enum 50040 CustomerType //fichero del enum
{
    Extensible = true;

    value(0; small)
    {
        Caption = 'small', Comment = 'pequeño';
    }
    value(1; medium)
    {
        Caption = 'medium', Comment = 'mediano';
    }
    value(2; big)
    {
        Caption = 'big', Comment = 'grande';
    }
}

fields //Tabla donde queremos incluir nuestro Enum
    {
        
        field(3; CustomerType; enum CustomerType)
        {
            Caption = 'Customer Type', Comment = 'Tipo Cliente';
        }
    }


/*  Crear un desplegable con información de una tabla desde el campo otra tabla */
     
        field(4; customerNo; Code[20])
        {           
           TableRelation = Customer."No."; // A) Condicion Normal
            TableRelation = Customer."No."where("Customer Posting Group" = const('UE')); // B) Condicion para que el grupo registro cliente que coincida con la constante UE             
        }


    /*  Campos que utilizan el valor calculado de otro campo para ser rellenados */

        field(5; CustomerNameNav; Text[50]) //asignación
        {            
            FieldClass = FlowField;
            CalcFormula = lookup (Customer.Name where("No." = field(customerNo)));
            // Buscar el campo Name de la tabla Customer, cuando el campo numero de la tabla destino coincida con nuestro campo CustomerNo
        }

        field(6; SumAount; Decimal) //Suma
        {
            Caption = 'Sum Amount', Comment = 'Saldo Cliente';
            FieldClass = FlowField;
            CalcFormula = sum ("Detailed Cust. Ledg. Entry".Amount where("Customer No." = field(customerNo), "Document Type" = filter('2..4'), "Entry No." = field(EntryNoFilter)));
            //Usamos el where para definir 2 filtros por defecto: Uno para el numero de cliente y otro para el tipo de documento
            // Al mismo tiempo, obligamos a que el numero que introduzcamos filtre por el Entry No. 
            Editable = false;
        }




/* Función que suma los totales de una columna y lo inicializa en una variable */

procedure SumInvoices(custCode: code[20]) totalAmount: Decimal
    var
        detCustLedgEntry: Record "Detailed Cust. Ledg. Entry";
    begin

        totalAmount := 0;
        detCustLedgEntry.SetRange("Document Type", detCustLedgEntry."Document Type"::Invoice);
        detCustLedgEntry.SetRange("Customer No.", custCode);
        if detCustLedgEntry.FindSet() then
            repeat

                totalAmount += detCustLedgEntry."Amount";

            until detCustLedgEntry.Next() = 0;
    end;




/*   Método para insertar un nuevo Cliente en una tabla No Estandar (FORM Customer)   */

procedure InsertNewCustomer(custNav: Record Customer)
    var
        custmForm: Record "FORM Customer";
        custmFormGetNO: Record "FORM Customer";
    //pageCustForm: Page "FORM Customer Card"; //Esto es del metodo 1

    begin

        if not Confirm(textForm001, true, custNav."No.") then
            exit;

        if not custmForm.get(custNav."No.") then begin
            Clear(custmForm);
            custmForm.Validate("No.", custNav."No.");
            custmForm.Insert(true);

        end;

        custmForm.Validate(description, custNav.Name);
        custmForm.Validate(customerNo, custNav."No.");

        custmForm.Modify(true);

        //Metodos para lanzar la pagina donde se encuentra el registro recien creado

        //Metodo 1

        /* custmForm.SetRange("No.", custNav."No.");
           pageCustForm.SetTableView(custmForm);
           pageCustForm.Run(); */

        //Metodo 2

        custmForm.SetRange("No.", custNav."No.");
        Page.Run(Page::"FORM Customer Card", custmForm);

    end;


    /*  Método para pasar un cliente a otra compañía    */

    procedure createCustOtherCompany(recCustomer: Record Customer)
    var

        custOtherCompany: Record Customer;
        company: Record Company;

    begin

        company.SetFilter(Name, '<>%1', CompanyName);
        if company.FindSet() then
            repeat

                custOtherCompany.ChangeCompany(company.Name);
                if custOtherCompany.Get(recCustomer."No.") then begin
                    custOtherCompany.TransferFields(recCustomer);
                    custOtherCompany.Modify(); //Sin el True
                end else begin
                    custOtherCompany.TransferFields(recCustomer);
                    custOtherCompany.Insert(); //Sin el True
                end;

                Message(textForm002, custOtherCompany.Name);

            until company.Next() = 0;

    end;

    /*  Función que produce un ajuste positivo o negativo de la cantidad de un producto en Movimientos de Productos, empleando el diario de Productos   */
     procedure SetRemainigQuantityDoingBalance(var ItemLedgerEntries: Record "Item Ledger Entry")

    var
        itemJournalLine: Record "Item Journal Line";
        lineNo: Integer;

    begin

        itemJournalLine.SetRange("Journal Batch Name", 'GENERICO');
        if itemJournalLine.FindSet() then itemJournalLine.DeleteAll();

        if ItemLedgerEntries.FindSet() then   // FUNCIÓN QUE RECORRE LA SELECCIÓN Y MUESTRA EL CODIGO DE CADA UNO DE ELLOS
            repeat
                // Message('Value =' + "Item No.");
                itemJournalLine.Validate("Journal Template Name", 'PRODUCTO');
                itemJournalLine.Validate("Journal Batch Name", 'GENERICO');
                if itemJournalLine.FindLast() then
                    lineNo := itemJournalLine."Line No." + 10000
                else
                    lineNo := 10000;
                itemJournalLine.Validate("Line No.", lineNo);
                itemJournalLine.Insert(true);

                itemJournalLine.Validate("Posting Date", Today);
                itemJournalLine.Validate("Item No.", ItemLedgerEntries."Item No.");
                itemJournalLine.Validate("Document No.", ItemLedgerEntries."Document No.");
                itemJournalLine.Validate(Description, ItemLedgerEntries.Description);
                itemJournalLine.Validate(Quantity, Abs(ItemLedgerEntries."Remaining Quantity"));
                if ItemLedgerEntries."Remaining Quantity" < 0 then
                    itemJournalLine.Validate("Entry Type", ItemLedgerEntries."Entry Type"::"Positive Adjmt.")
                else
                    itemJournalLine.Validate("Entry Type", ItemLedgerEntries."Entry Type"::"Negative Adjmt.");

                itemJournalLine.Validate("EntryNo.", ItemLedgerEntries."Entry No.");
                itemJournalLine.Modify(true);

            until ItemLedgerEntries.Next() = 0;

        Message('Datos introducidos correctamente');

        Codeunit.Run(Codeunit::"Item Jnl.-Post", itemJournalLine);

         end;


        /*  Evento de la acción 'Registrar' (Añadimos los valores de la Factura, con IRPF, a una tabla nuestra: Retention Movements) */


    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Purch.-Post", 'OnAfterInsertPostedHeaders', '', true, true)]

    local procedure OnAfterInserPostedHeader(var PurchInvHeader: Record "Purch. Inv. Header")
    var
        recFormRetentionMovement: Record "Form Retention Movements";

        PurchaseHeader: Record "Purchase Header";
        FormIRPF: Record "Form IRPF";
        recVendor: Record Vendor;
        IRPF_Code: Code[20];
        "%IRPF": Integer;
        previusInvoiceNO: Code[20];
        Amount: Decimal;
        CalcAmount: Decimal;

    begin

        recVendor.Get(PurchInvHeader."Buy-from Vendor No.");

        FormIRPF.Get(recVendor."IRPF No.");

        PurchaseHeader.Get(PurchaseHeader."Document Type"::Invoice, PurchInvHeader."Pre-Assigned No."); //Nos posicionamos con clave compuesta en la cabecera
        PurchaseHeader.CalcFields(Amount);

        recFormRetentionMovement.SetRange("Doc No.", PurchInvHeader."No.");
        //if not recFormRetentionMovement.get(PurchInvHeader."No.") then begin
        Clear(recFormRetentionMovement);
        recFormRetentionMovement.Validate("Doc No.", PurchInvHeader."No.");
        recFormRetentionMovement.Insert(true);
        //end;

        recFormRetentionMovement.Validate(Posting_Date, PurchInvHeader."Posting Date");
        recFormRetentionMovement.Validate("Vendor No.", PurchInvHeader."Buy-from Vendor No.");
        recFormRetentionMovement.Validate(IRPF_Code, recVendor."IRPF No.");
        recFormRetentionMovement.Validate(Quantity, 1);
        recFormRetentionMovement.Validate(Amount, PurchaseHeader.Amount * (FormIRPF."%IRPF" / 100));

        recFormRetentionMovement.Modify(true);


    end;    


    /* Evento que inserta los valores de IRPF de una factura registrada en el Diario de compra. (Paso 1/2) */

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Purch.-Post", 'OnBeforePostVendorEntry', '', false, false)]


    local procedure OnBeforePostVendorEntry(var GenJnlLine: Record "Gen. Journal Line"; var PurchHeader: Record "Purchase Header";
                            var GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line"; var TotalPurchLine: Record "Purchase Line";
                            var TotalPurchLineLCY: Record "Purchase Line")

    var

        vendorRecord: Record Vendor;
        IRPFRec: Record "Form IRPF";

    begin

        vendorRecord.Get(PurchHeader."Buy-from Vendor No.");
        GenJnlLine.Validate(IRPF_Code, PurchHeader."IRPF No.");
        IRPFRec.Get(GenJnlLine.IRPF_Code);
        GenJnlLine.Validate(IRPF_Percent, IRPFRec."%IRPF");
        TotalPurchLine.SetRange(isIRPF, true);
        if TotalPurchLine.FindSet() then
            GenJnlLine.Validate(IRPF_Amount, TotalPurchLine."Direct Unit Cost");
    end;


   /*  Evento para que nos inserte los valores de IRPF del Diario de compra en la tabla Movimientos de Proveedores (Paso 2/2)
 */

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Gen. Jnl.-Post Line", 'OnBeforeVendLedgEntryInsert', '', false, false)]


    local procedure OnBeforeVendLedgEntryInsert(GenJournalLine: Record "Gen. Journal Line"; var VendorLedgerEntry: Record "Vendor Ledger Entry")

    begin

        VendorLedgerEntry.Validate(IRPF_Cod, GenJournalLine.IRPF_Code);
        VendorLedgerEntry.Validate("IRPF%", GenJournalLine.IRPF_Percent);
        VendorLedgerEntry.Validate(IRPF_Amount, GenJournalLine.IRPF_Amount);

    end;


    /*   Reports: Como crear un Lookup para filtrar desde la RequestPage   */

requestpage
    {
        layout
        {
            area(content)
            {
                group(GroupName)
                {
                    field(Name; cust.Name)
                    {
                        ApplicationArea = All;
                        trigger OnLookup(var Text: Text): Boolean
                        var
                            pageCustLookUp: Page "Customer Lookup"; //instancia pagina lookup de clientes

                        begin

                            pageCustLookUp.LookupMode(true); //Activar el modo lookup de la pagina
                            if pageCustLookUp.RunModal() = Action::LookupOK then //Si pulsamos sobre una fila del registro, entonces
                                pageCustLookUp.GetRecord(cust); //Obtiene el registro (clave primaria -> No.)

                        end;

                    }                    
                }
            }
        }
    }



    /*   Como filtrar por fecha en un report   */

 dataset
    {

    dataitem("SalInvHeader"; "Sales Invoice Header")
        {          

            column(Posting_Date; "Posting Date") { } //Fecha registro   

            //____________ filtrar en la RequestPage por "Posting Date" _________________

            trigger OnPreDataItem()
            var
            begin
                if dateFilter <> 0D then
                    SetRange("Posting Date", dateFilter);
            end;
        }
    }

requestpage
    {
        layout
        {
            area(content)
            {
                group(Filters)
                {
                    field(Posting_Date; dateFilter)
                    {
                        ApplicationArea = All;

                    }
                }
            }
        }
    }

    var          
        dateFilter: Date;     




        /*   Generar un Logo en un REPORT   */   


dataset
    {      

        dataitem("SalInvHeader"; "Sales Invoice Header")
        {        

            column(Logo; cominf.Picture) { }

        }
    }

     trigger OnPreReport()
    var
    begin
        cominf.get();
        format.Company(arrayCompany, cominf);
        cominf.calcfields(Picture);
    end;

     var
        format: Codeunit "Format Address"; // Estandar de navision - toda la informacion de la direccion para los documentos;  ¡¡IMPORTANTE!!

        cominf: Record "Company Information"; 

        arrayCompany: array[8] of Text[100];


        








