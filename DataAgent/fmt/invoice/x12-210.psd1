@{
    Key = 'b302'
    Detail = @('l5*', 'l0*', 'l1*')
    Values = @{}
    Control = ''
    Dates = @{}
    Separator = '*'
    Terminator = ''
    SeDetailCount = $null
    Head = @(
        'ISA*00*          *00*          *02*{sender_id,-15}*ZZ*{receiver_id,-15}*{now:yyMMdd}*{now:HHmm}*U*00401*{control:000000000}*0*P*>'
        'GS*IM*{sender_id}*{receiver_id}*{now:yyyyMMdd}*{now:HHmm}*{control}*X*004010'
    )
    Invoice = @(
        'ST*210*{st:000000000}'
        'B3**{b302}*{b303}*PP**{b306}*{b307}**{b309}*035*{sender_id}*{b312}'
        'N9*D*BM*{b303}'
        'N1*SH*{company_name}'
        'N3*{company_address}'
        'N4*{company_city}*{company_state}*{company_zip}'
        'N1*SF*{n102_sf}'
        'N3*{n301_sf}'
        'N4*{n401_sf}*{n402_sf}*{n403_sf}'
        'N1*CN*{n102_cn}*92*{n104_cn}'
        'N3*{n301_cn}'
        'N4*{n401_cn}*{n402_cn}*{n403_cn}'
    )
    Line = @('LX*{lx:000}', 'L5*{lx:000}*{l502}*****{l507}', 'L0*{lx:000}***{l004}*PG*{l006}*G', 'L1*{lx:000}*{l102}*PG*{l104}')
    Close = @('L3*{l301}*G***{b307}')
    Se = 'SE*{se}*{st:000000000}'
    SeExtra = 0
    Tail = @('GE*{invoices}*{control}', 'IEA*1*{control:000000000}')
}
