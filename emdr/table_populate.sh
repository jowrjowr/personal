for i in `mysql -e "select regionID from mapRegions where regionID = 10000002" eve_static -BN`; do
#for i in `mysql -e "select regionID from mapRegions where regionID < 11000000" eve_static -BN`; do

mysql -e "create table "$i"_orders(gendate BIGINT,  typeID INT, price DECIMAL(16,2) NOT NULL, volRemaining INT , \`range\` INT, orderID BIGINT, volEntered INT, minVolume INT, \`bid\` INT, issueDate BIGINT, \`duration\` INT, stationID INT, solarSystemID INT) ENGINE=InnoDB" emdr
mysql -e "create table "$i"_history (gendate BIGINT, typeID INT, date BIGINT, orders INT, low DECIMAL(16,2), high DECIMAL(16,2), \`average\` DECIMAL(16,2), quantity BIGINT) ENGINE=InnoDB" emdr
mysql -e "create index idx on "$i"_history(typeID, date)" emdr
mysql -e "create unique index idx on "$i"_orders(typeID,orderID)" emdr

mysql -e "alter table "$i"_history partition by range(typeID) (
partition p0 values less than (5000), partition p1 values less than (10000), partition p2 values less than (15000), partition p3 values less than (20000),
partition p4 values less than (25000), partition p5 values less than (30000), partition p6 values less than (35000), partition p7 values less than (MAXVALUE))" emdr

mysql -e "alter table "$i"_orders partition by range columns (typeID,orderID) (
partition p0 values less than (5000,0), partition p1 values less than (5000,MAXVALUE), partition p2 values less than (10000,0), partition p3 values less than (10000,MAXVALUE),
partition p4 values less than (15000,0), partition p5 values less than (15000,MAXVALUE), partition p6 values less than (20000,0), partition p7 values less than (20000,MAXVALUE),
partition p8 values less than (25000,0), partition p9 values less than (25000,MAXVALUE), partition p10 values less than (30000,0), partition p11 values less than (30000,MAXVALUE),
partition p12 values less than (35000,0), partition p13 values less than (35000,MAXVALUE), partition p14 values less than (MAXVALUE,MAXVALUE))" emdr


done
