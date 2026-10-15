@{
    Values = @{}
    Head = @('{dtn.user},{dtn.pass}', 'INF')
    Start = 1001
    Open = @('C02,{n},  /  /  ,00:00,COMP,2,0001,S', '{dtn.site}', 'BEGIN-BINARY-DATA')
    Header = @('INVH', '{sender_id}', '{ivh_invoicenumber}', '', '{ivh_billdate}', 'PR', '{ivh_billto}', '{ivh_consignee}', '{ivh_consignee}', '{po}', '{ShipperName}', '{ShipperAddress1}', '{ShipperAddress2}', '{ShipperCity}', '{ShipperState}', '{ShipperZip}', '{ConsigneeName}', '{ivh_consignee}', '{ConsigneeAddress1}', '{ConsigneeAddress2}', '{ConsigneeCity}', '{ConsigneeState}', '{ConsigneeZip}', 'UNK', '{terms}', '{ivh_totalcharge}', '{ivh_billdate}', '{ivh_totalcharge}', '0.00', '', '', '', '', '', '')
    Detail = 'Detail'
    Line = @('{RecordType}', '{bol}', '{ivd_description}', '{cmd_code}', 'G', '{ivd_quantity}', '{ivd_wgt}', '{ivd_quantity}', '{ivd_unit}', '{ivd_rate:0.0000}', '{ivd_charge:0.00}', '{invoice.ShipDate}', '{invoice.ShipTime}', '', '', '')
    Close = @('END-BINARY-DATA')
    Tail = @('<!--END OF FILE-->')
}
