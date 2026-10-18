import { LightningElement, api, wire } from 'lwc';
import {
    getRecord,
    getFieldValue,
    notifyRecordUpdateAvailable
} from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getOffers from '@salesforce/apex/OfferController.getOffers';
import canApproveOffers from '@salesforce/apex/OfferController.canApproveOffers';
import submitOffer from '@salesforce/apex/OfferController.submitOffer';
import approveOffer from '@salesforce/apex/OfferController.approveOffer';
import acceptOffer from '@salesforce/apex/OfferController.acceptOffer';
import rejectOffer from '@salesforce/apex/OfferController.rejectOffer';

import PRICE_FIELD from '@salesforce/schema/Property__c.Price__c';
import STATUS_FIELD from '@salesforce/schema/Property__c.Status__c';

export const APPROVAL_THRESHOLD_PERCENT = 10;

const OPEN_STATUSES = ['Submitted', 'Needs Approval', 'Approved'];
const BADGE_CLASSES = {
    Submitted: 'slds-badge',
    'Needs Approval': 'slds-badge slds-theme_warning',
    Approved: 'slds-badge slds-theme_info',
    Accepted: 'slds-badge slds-theme_success',
    Rejected: 'slds-badge slds-badge_lightest'
};
const ACTIONS = {
    approve: { apex: approveOffer, message: 'Offer approved' },
    accept: {
        apex: acceptOffer,
        message: 'Offer accepted. Property is now Under Agreement'
    },
    reject: { apex: rejectOffer, message: 'Offer rejected' }
};

export default class PropertyOffers extends LightningElement {
    @api recordId;

    buyerName = '';
    amount;
    isSaving = false;
    wiredOffers;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [PRICE_FIELD, STATUS_FIELD]
    })
    property;

    @wire(canApproveOffers)
    canApprove;

    @wire(getOffers, { propertyId: '$recordId' })
    offersResult(result) {
        this.wiredOffers = result;
    }

    get askingPrice() {
        return getFieldValue(this.property.data, PRICE_FIELD);
    }

    get isClosed() {
        return getFieldValue(this.property.data, STATUS_FIELD) === 'Closed';
    }

    get cardTitle() {
        const count = this.wiredOffers?.data?.length ?? 0;
        return `Offers (${count})`;
    }

    get previewPercent() {
        if (!this.askingPrice || !this.amount) {
            return null;
        }
        return ((this.askingPrice - this.amount) / this.askingPrice) * 100;
    }

    get hasPreview() {
        return this.previewPercent !== null;
    }

    get previewLabel() {
        const pct = this.previewPercent;
        if (pct === null) {
            return '';
        }
        const rounded = Math.abs(pct).toFixed(1);
        return pct >= 0
            ? `${rounded}% below asking`
            : `${rounded}% above asking`;
    }

    get previewNeedsApproval() {
        return this.previewPercent > APPROVAL_THRESHOLD_PERCENT;
    }

    get previewClass() {
        return this.previewNeedsApproval
            ? 'slds-text-color_error'
            : 'slds-text-color_success';
    }

    get thresholdLabel() {
        return `${APPROVAL_THRESHOLD_PERCENT}%`;
    }

    get submitDisabled() {
        return this.isSaving || this.isClosed;
    }

    get offers() {
        const data = this.wiredOffers?.data;
        if (!data) {
            return [];
        }
        const canApprove = this.canApprove?.data === true;
        return data.map((offer) => {
            const isOpen = OPEN_STATUSES.includes(offer.Status__c);
            const needsApproval = offer.Status__c === 'Needs Approval';
            return {
                ...offer,
                discountLabel: this.formatDiscount(offer.Discount_Percent__c),
                badgeClass: BADGE_CLASSES[offer.Status__c] ?? 'slds-badge',
                showApprove: needsApproval && canApprove,
                showAccept: isOpen && !needsApproval,
                showReject: isOpen
            };
        });
    }

    get hasOffers() {
        return this.offers.length > 0;
    }

    get error() {
        return this.wiredOffers?.error || this.property?.error;
    }

    formatDiscount(value) {
        if (value === null || value === undefined) {
            return '';
        }
        return value >= 0
            ? `${value}% below asking`
            : `${Math.abs(value)}% above asking`;
    }

    handleBuyerChange(event) {
        this.buyerName = event.target.value;
    }

    handleAmountChange(event) {
        const value = event.target.value;
        this.amount = value === '' || value === null ? null : Number(value);
    }

    async handleSubmit() {
        const inputs = [...this.template.querySelectorAll('lightning-input')];
        const valid = inputs.reduce(
            (ok, input) => input.reportValidity() && ok,
            true
        );
        if (!valid) {
            return;
        }
        this.isSaving = true;
        try {
            const offer = await submitOffer({
                propertyId: this.recordId,
                buyerName: this.buyerName,
                amount: this.amount
            });
            this.toast(
                offer.Status__c === 'Needs Approval'
                    ? 'Offer submitted. Broker approval required'
                    : 'Offer submitted',
                offer.Status__c === 'Needs Approval' ? 'warning' : 'success'
            );
            this.buyerName = '';
            this.amount = null;
            await refreshApex(this.wiredOffers);
        } catch (error) {
            this.toast(this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleAction(event) {
        const { id, action } = event.target.dataset;
        const config = ACTIONS[action];
        this.isSaving = true;
        try {
            await config.apex({ offerId: id });
            this.toast(config.message, 'success');
            await refreshApex(this.wiredOffers);
            if (action === 'accept') {
                await notifyRecordUpdateAvailable([
                    { recordId: this.recordId }
                ]);
            }
        } catch (error) {
            this.toast(this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }

    toast(title, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, variant }));
    }
}
