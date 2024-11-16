<?xml version="1.0" encoding="UTF-8"?>
<Profile xmlns="http://soap.sforce.com/2006/04/metadata">
    <classAccesses>
        <apexClass>StudentAccount</apexClass>
        <enabled>false</enabled>
    </classAccesses>
    <custom>true</custom>
    <fieldPermissions>
        <editable>false</editable>
        <field>Address.Address_Type__c</field>
        <readable>false</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Student__c.GPA__c</field>
        <readable>false</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Student__c.Student_Id__c</field>
        <readable>false</readable>
    </fieldPermissions>
    <layoutAssignments>
        <layout>Address-Address Layout</layout>
    </layoutAssignments>
    <layoutAssignments>
        <layout>Address-Address Layout</layout>
        <recordType>Address.Home</recordType>
    </layoutAssignments>
    <layoutAssignments>
        <layout>Address-Address Layout</layout>
        <recordType>Address.Work_School</recordType>
    </layoutAssignments>
    <layoutAssignments>
        <layout>Student__c-Student Layout</layout>
    </layoutAssignments>
    <layoutAssignments>
        <layout>Student__c-Student Layout</layout>
        <recordType>Student__c.Course</recordType>
    </layoutAssignments>
    <layoutAssignments>
        <layout>Student__c-Student Layout</layout>
        <recordType>Student__c.Courses</recordType>
    </layoutAssignments>
    <layoutAssignments>
        <layout>Student__c-Student Layout</layout>
        <recordType>Student__c.Type</recordType>
    </layoutAssignments>
    <pageAccesses>
        <apexPage>StudentContact</apexPage>
        <enabled>false</enabled>
    </pageAccesses>
    <recordTypeVisibilities>
        <default>true</default>
        <recordType>Address.Home</recordType>
        <visible>true</visible>
    </recordTypeVisibilities>
    <recordTypeVisibilities>
        <default>false</default>
        <recordType>Address.Work_School</recordType>
        <visible>true</visible>
    </recordTypeVisibilities>
    <recordTypeVisibilities>
        <default>false</default>
        <recordType>Student__c.Course</recordType>
        <visible>false</visible>
    </recordTypeVisibilities>
    <recordTypeVisibilities>
        <default>false</default>
        <recordType>Student__c.Courses</recordType>
        <visible>false</visible>
    </recordTypeVisibilities>
    <recordTypeVisibilities>
        <default>false</default>
        <recordType>Student__c.Type</recordType>
        <visible>false</visible>
    </recordTypeVisibilities>
    <userLicense>External Apps Login</userLicense>
    <userPermissions>
        <enabled>true</enabled>
        <name>EnableNotifications</name>
    </userPermissions>
    <userPermissions>
        <enabled>true</enabled>
        <name>SelectFilesFromSalesforce</name>
    </userPermissions>
</Profile>
