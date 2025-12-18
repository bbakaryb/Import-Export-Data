import { LightningElement, api, track } from 'lwc';
import getObjectApiNameFromRecordId from '@salesforce/apex/Import_Export_Data.getObjectApiNameFromRecordId';
import listFields from '@salesforce/apex/Import_Export_Data.listFields';
import exportCsv from '@salesforce/apex/Import_Export_Data.exportCsv';
import importCsv from '@salesforce/apex/Import_Export_Data.importCsv';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class Lwc01_DataPorter extends LightningElement {

  @api recordId;
    selectedObject = '';
    fields = [];
    selectedFields = [];
    orderedFields = [];
    isLoading = false;
    message = '';

    connectedCallback() {
        if (this.recordId) {
            getObjectApiNameFromRecordId({ recordId: this.recordId })
                .then(objName => {
                    this.selectedObject = objName;
                    return listFields({ objectName: objName });
                })
                .then(flds => {
                    this.fields = flds.map(f => ({ label: f, value: f }));
                })
                .catch(err => {
                    this.message = 'Erreur: ' + (err.body ? err.body.message : err.message);
                });
        }
    }

    handleFieldsChange(e) {
        this.selectedFields = e.detail.value;
        let newOrdered = [];

        // Conserve precedent order
        for (let ofld of this.orderedFields) {
            if (this.selectedFields.includes(ofld.value)) newOrdered.push(ofld);
        }
        // Add new field in the end
        for (let f of this.selectedFields) {
            if (!newOrdered.find(x => x.value === f)) {
                newOrdered.push({ label: f, value: f, index: newOrdered.length });
            }
        }
        this.orderedFields = newOrdered.map((f, i) => ({ ...f, index: i }));
    }

    swapOrder(i, j) {
        const tmp = this.orderedFields[i];
        this.orderedFields[i] = this.orderedFields[j];
        this.orderedFields[j] = tmp;
        this.orderedFields = this.orderedFields.map((f, idx) => ({ ...f, index: idx }));
    }

    moveUp(evt) {
        const idx = parseInt(evt.target.dataset.index, 10);
        if (idx > 0) this.swapOrder(idx, idx - 1);
    }

    moveDown(evt) {
        const idx = parseInt(evt.target.dataset.index, 10);
        if (idx < this.orderedFields.length - 1) this.swapOrder(idx, idx + 1);
    }

    removeField(evt) {
        const idx = parseInt(evt.target.dataset.index, 10);
        this.orderedFields.splice(idx, 1);
        this.orderedFields = this.orderedFields.map((f, i) => ({ ...f, index: i }));
        this.selectedFields = this.orderedFields.map(f => f.value);
    }

    async handleExport() {
        if (!this.selectedFields.length) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Selected one field before export.',
                variant: 'error'
            }));
            return;
        }

        this.isLoading = true;
        try {
            const base64Data = await exportCsv({
                objectName: this.selectedObject,
                orderedFields: this.selectedFields,
                recordId: this.recordId
            });

            const blobUrl = 'data:application/octet-stream;base64,' + base64Data;
            const link = document.createElement('a');
            link.href = blobUrl;
            link.download = `${this.selectedObject}_export.csv`;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);

            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Field export.',
                variant: 'success'
            }));
        } catch (error) {
            console.error(error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || error.message,
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    handleFileChange(event) {
        if (event.target.files.length > 0) {
            this.file = event.target.files[0];
        }
    }

    async handleImport() {
    if (!this.file) {
        alert('Selected CSV file.');
        return;
    }

    const reader = new FileReader();

    reader.onload = async () => {
        try {

            const arrayBuffer = reader.result;

            // Conversion ArrayBuffer → Base64 
            let binary = '';
            const bytes = new Uint8Array(arrayBuffer);
            const len = bytes.byteLength;

            for (let i = 0; i < len; i++) {
                binary += String.fromCharCode(bytes[i]);
            }

            const base64Data = btoa(binary);

            const result = await importCsv({
                objectName: this.selectedObject,
                base64Csv: base64Data
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Import finished',
                    message: `${result.inserted} success, ${result.failed} errors.`,
                    variant: result.failed > 0 ? 'warning' : 'success'
                })
            );
        } catch (error) {
            console.error(error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Import error',
                    message: error.body ? error.body.message : error.message,
                    variant: 'error'
                })
            );
        }
    };

    reader.readAsArrayBuffer(this.file);
}



}