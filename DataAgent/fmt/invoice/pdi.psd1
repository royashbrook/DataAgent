@{
    Key = 'ivh_invoicenumber'
    Head = 'ivh*'
    Type = 'dori'
    Values = @{}
    Footer = ''
    H = '"H","{sender_id}","{ivh_invoicenumber}","{ivh_billdate}",,,,,,"{ivh_totalcharge}","N"'
    D = '"D","{ivd_refnum}","{ivh_consignee}","{cmd_code}","{not_text}","{sender_id}",,"{ivd_quantity}","{ivd_wgt}","{ivd_rate}",,"{ivd_charge}",'
    I = '"I","{cht_itemcode}","{ivd_charge}",'
}
