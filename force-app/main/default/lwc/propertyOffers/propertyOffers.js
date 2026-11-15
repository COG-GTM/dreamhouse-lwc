import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import {
    getRecord,
    getFieldValue,
    notifyRecordUpdateAvailable
} from 'lightning/uiRecordApi';
import PRICE_FIELD from '@salesforce/schema/Property__c.Price__c';
import STATUS_FIELD from '@salesforce/schema/Property__c.Status__c';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOffers from '@salesforce/apex/PropertyOffersController.getOffers';
import submitOffer from '@salesforce/apex/PropertyOffersController.submitOffer';
import approveOffer from '@salesforce/apex/PropertyOffersController.approveOffer';
import acceptOffer from '@salesforce/apex/PropertyOffersController.acceptOffer';
import rejectOffer from '@salesforce/apex/PropertyOffersController.rejectOffer';

export default class PropertyOffers extends LightningElement {
    @api recordId;
    buyerName = '';
    amount = '';
    busy = false;
    data;
    wiredResult;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [PRICE_FIELD, STATUS_FIELD]
    })
    async wiredProperty({ data }) {
        if (
            data &&
            this.data &&
            (getFieldValue(data, PRICE_FIELD) !== this.data.askingPrice ||
                getFieldValue(data, STATUS_FIELD) !== this.data.propertyStatus)
        ) {
            try {
                await refreshApex(this.wiredResult);
            } catch (error) {
                this.showError(error);
            }
        }
    }

    @wire(getOffers, { propertyId: '$recordId' })
    wiredOffers(result) {
        this.wiredResult = result;
        if (result.data) {
            this.data = result.data;
        } else if (result.error) {
            this.showError(result.error);
        }
    }

    get title() {
        return 'Offers (' + (this.data?.offers?.length || 0) + ')';
    }
    get offers() {
        return (this.data?.offers || []).map((offer) => ({
            ...offer,
            showApprove:
                offer.Status__c === 'Needs Approval' && this.data.canApprove,
            showAccept: ['Submitted', 'Approved'].includes(offer.Status__c),
            showReject: !['Accepted', 'Rejected'].includes(offer.Status__c)
        }));
    }
    get empty() {
        return this.offers.length === 0;
    }
    get unavailable() {
        return ['Closed', 'Under Agreement'].includes(
            this.data?.propertyStatus
        );
    }
    get submitDisabled() {
        return this.busy || this.unavailable || !this.data;
    }
    get preview() {
        const price = Number(this.data?.askingPrice);
        const amount = Number(this.amount);
        if (!(price > 0) || !(amount > 0)) {
            return '';
        }
        const raw = ((price - amount) / price) * 100;
        const magnitude = Math.abs(raw);
        const rounded =
            (Math.sign(raw) *
                Math.round(
                    (magnitude + Number.EPSILON * Math.max(1, magnitude)) * 10
                )) /
            10;
        return (
            rounded.toFixed(1) +
            '% below asking' +
            (rounded > 10 ? ', needs broker approval' : '')
        );
    }
    handleBuyer(event) {
        this.buyerName = event.target.value;
    }
    handleAmount(event) {
        this.amount = event.target.value;
    }
    async handleSubmit() {
        const valid = [...this.template.querySelectorAll('lightning-input')]
            .map((input) => input.reportValidity())
            .every(Boolean);
        if (!valid || this.submitDisabled) {
            return;
        }
        this.busy = true;
        try {
            await submitOffer({
                propertyId: this.recordId,
                buyerName: this.buyerName,
                amount: Number(this.amount)
            });
            this.buyerName = '';
            this.amount = '';
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.showError(error);
        } finally {
            this.busy = false;
        }
    }
    async handleAction(event) {
        if (this.busy) {
            return;
        }
        const { id, action } = event.target.dataset;
        const actions = {
            approve: approveOffer,
            accept: acceptOffer,
            reject: rejectOffer
        };
        this.busy = true;
        try {
            await actions[action]({ offerId: id });
            await refreshApex(this.wiredResult);
            if (action === 'accept') {
                await notifyRecordUpdateAvailable([
                    { recordId: this.recordId }
                ]);
            }
        } catch (error) {
            this.showError(error);
        } finally {
            this.busy = false;
        }
    }
    showError(error) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Offer error',
                message:
                    error?.body?.message ||
                    error?.message ||
                    'Unable to update offers.',
                variant: 'error'
            })
        );
    }
}
